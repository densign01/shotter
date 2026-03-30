import AppKit
import SwiftUI

func annotationImageRect(in viewSize: CGSize, imageSize: CGSize) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0 else { return .zero }

    let imageAspect = imageSize.width / imageSize.height
    let viewAspect = viewSize.width / viewSize.height

    let scaledSize: CGSize
    if imageAspect > viewAspect {
        scaledSize = CGSize(
            width: viewSize.width,
            height: viewSize.width / imageAspect
        )
    } else {
        scaledSize = CGSize(
            width: viewSize.height * imageAspect,
            height: viewSize.height
        )
    }

    let origin = CGPoint(
        x: (viewSize.width - scaledSize.width) / 2,
        y: (viewSize.height - scaledSize.height) / 2
    )

    return CGRect(origin: origin, size: scaledSize)
}

/// NSView that handles the annotation canvas rendering and mouse events
class AnnotationCanvasView: NSView {
    // Weak reference to avoid retaining state after window closes.
    // The window owns state; canvas should not extend its lifetime.
    weak var state: AnnotationEditorState?
    private var trackingArea: NSTrackingArea?

    // Cached CIContext for blur operations (expensive to create)
    private let ciContext = CIContext()

    // Scale and offset for zooming/panning
    var scale: CGFloat = 1.0
    var offset: CGPoint = .zero

    // Pan tracking
    private var isPanning = false
    private var panStartPoint: NSPoint = .zero
    private var panStartOffset: CGPoint = .zero
    
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }  // Use standard macOS coordinates
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.focusCanvas()
        }
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext,
              let state = state else { return }
        
        // Clear background
        context.setFillColor(NSColor.controlBackgroundColor.cgColor)
        context.fill(bounds)
        
        // Calculate image position (centered)
        let imageRect = imageRectInView()
        
        // Draw checkerboard pattern behind image (for transparency)
        drawCheckerboard(in: imageRect, context: context)
        
        // Draw base image
        state.baseImage.draw(in: imageRect)
        
        // Draw blur regions
        for anyAnnotation in state.annotations {
            if let blurAnnotation = anyAnnotation.annotation as? BlurAnnotation {
                drawBlurRegion(blurAnnotation, in: context, imageRect: imageRect)
            }
        }
        
        // Draw annotations
        context.saveGState()
        context.translateBy(x: imageRect.origin.x, y: imageRect.origin.y)
        context.scaleBy(x: scale, y: scale)
        
        for anyAnnotation in state.annotations {
            if !(anyAnnotation.annotation is BlurAnnotation) {
                anyAnnotation.annotation.render(in: context, scale: scale)
            }
        }
        
        // Draw selection handles for selected annotation
        if let selectedId = state.selectedAnnotationId,
           let annotation = state.annotations.first(where: { $0.id == selectedId }) {
            drawSelectionHandles(for: annotation.annotation, in: context)
        }
        
        context.restoreGState()

        // Draw crop overlay if active
        if let cropRect = state.cropRect {
            let scaledCropRect = CGRect(
                x: imageRect.origin.x + cropRect.origin.x * scale,
                y: imageRect.origin.y + cropRect.origin.y * scale,
                width: cropRect.width * scale,
                height: cropRect.height * scale
            )

            // Dark overlay outside crop area using even-odd rule
            context.saveGState()
            context.clip(to: imageRect)
            context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            let path = CGMutablePath()
            path.addRect(imageRect)
            path.addRect(scaledCropRect)
            context.addPath(path)
            context.fillPath(using: .evenOdd)

            // Dashed border around crop area
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(2)
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.stroke(scaledCropRect)
            context.restoreGState()
        }
    }

    private func imageRectInView() -> CGRect {
        guard let state = state else { return .zero }

        // Base fit-to-view rect
        let fitRect = annotationImageRect(in: bounds.size, imageSize: state.imageSize)
        let baseScale = fitRect.width / state.imageSize.width

        // Apply zoom level from state
        let zoomedScale = baseScale * state.zoomLevel
        scale = zoomedScale

        let zoomedWidth = state.imageSize.width * zoomedScale
        let zoomedHeight = state.imageSize.height * zoomedScale

        // Center in view, then offset by pan
        let originX = (bounds.width - zoomedWidth) / 2 + state.panOffset.x
        let originY = (bounds.height - zoomedHeight) / 2 + state.panOffset.y

        return CGRect(x: originX, y: originY, width: zoomedWidth, height: zoomedHeight)
    }
    
    private func drawCheckerboard(in rect: CGRect, context: CGContext) {
        let tileSize: CGFloat = 10
        let light = NSColor.white.cgColor
        let dark = NSColor(white: 0.9, alpha: 1).cgColor
        
        context.saveGState()
        context.clip(to: rect)
        
        let cols = Int(ceil(rect.width / tileSize))
        let rows = Int(ceil(rect.height / tileSize))
        
        for row in 0..<rows {
            for col in 0..<cols {
                let isLight = (row + col) % 2 == 0
                context.setFillColor(isLight ? light : dark)
                context.fill(CGRect(
                    x: rect.origin.x + CGFloat(col) * tileSize,
                    y: rect.origin.y + CGFloat(row) * tileSize,
                    width: tileSize,
                    height: tileSize
                ))
            }
        }
        
        context.restoreGState()
    }
    
    private func drawBlurRegion(_ blur: BlurAnnotation, in context: CGContext, imageRect: CGRect) {
        guard let state = state,
              let cgImage = state.baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        
        // Transform blur bounds to view coordinates
        let scaledBounds = CGRect(
            x: imageRect.origin.x + blur.bounds.origin.x * scale,
            y: imageRect.origin.y + blur.bounds.origin.y * scale,
            width: blur.bounds.width * scale,
            height: blur.bounds.height * scale
        )
        
        // Only proceed if blur region has meaningful size
        guard scaledBounds.width > 2 && scaledBounds.height > 2 else { return }
        
        context.saveGState()
        context.clip(to: scaledBounds)
        
        // Apply blur using Core Image
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIGaussianBlur") else {
            context.restoreGState()
            return
        }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(blur.blurRadius, forKey: kCIInputRadiusKey)

        if let outputImage = filter.outputImage {
            // Extend the crop rect to account for blur edge effects
            let cropRect = ciImage.extent.insetBy(dx: -blur.blurRadius * 2, dy: -blur.blurRadius * 2)
            if let blurredCGImage = ciContext.createCGImage(outputImage, from: cropRect) {
                // Adjust drawing rect to account for extended crop
                let adjustedRect = CGRect(
                    x: imageRect.origin.x - blur.blurRadius * 2 * scale,
                    y: imageRect.origin.y - blur.blurRadius * 2 * scale,
                    width: imageRect.width + blur.blurRadius * 4 * scale,
                    height: imageRect.height + blur.blurRadius * 4 * scale
                )
                context.draw(blurredCGImage, in: adjustedRect)
            }
        }
        
        context.restoreGState()
        
        // Draw border if selected
        if blur.isSelected {
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(2)
            context.setLineDash(phase: 0, lengths: [5, 3])
            context.stroke(scaledBounds)
        }
    }
    
    private func drawSelectionHandles(for annotation: any Annotation, in context: CGContext) {
        let handles = annotation.resizeHandles()
        
        for handle in handles {
            // Outer ring
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: handle.rect.insetBy(dx: -1, dy: -1))
            
            // Inner fill
            context.setFillColor(NSColor.systemBlue.cgColor)
            context.fillEllipse(in: handle.rect)
        }
        
        // Draw selection border
        context.setStrokeColor(NSColor.systemBlue.cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [])
        context.stroke(annotation.bounds)
    }
    
    // MARK: - Coordinate Conversion
    
    func viewPointToImagePoint(_ viewPoint: CGPoint) -> CGPoint {
        let imageRect = imageRectInView()
        return CGPoint(
            x: (viewPoint.x - imageRect.origin.x) / scale,
            y: (viewPoint.y - imageRect.origin.y) / scale
        )
    }
    
    func imagePointToViewPoint(_ imagePoint: CGPoint) -> CGPoint {
        let imageRect = imageRectInView()
        return CGPoint(
            x: imageRect.origin.x + imagePoint.x * scale,
            y: imageRect.origin.y + imagePoint.y * scale
        )
    }
    
    // MARK: - Mouse Events
    
    override func mouseDown(with event: NSEvent) {
        guard let state = state else { return }

        focusCanvas()
        
        let viewPoint = convert(event.locationInWindow, from: nil)
        let imagePoint = viewPointToImagePoint(viewPoint)
        
        // Check if within image bounds
        let imageBounds = CGRect(origin: .zero, size: state.imageSize)
        guard imageBounds.contains(imagePoint) else {
            state.selectAnnotation(nil)
            needsDisplay = true
            return
        }
        
        // Handle double-click for text editing
        if event.clickCount == 2 {
            for annotation in state.annotations.reversed() {
                if annotation.annotation is TextAnnotation,
                   annotation.annotation.hitTest(point: imagePoint, tolerance: 5) {
                    state.selectAnnotation(annotation.id)
                    state.editingTextAnnotationId = annotation.id
                    needsDisplay = true
                    return
                }
            }
        }
        
        state.currentTool.mouseDown(at: imagePoint, state: state)
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let state = state else { return }
        
        let viewPoint = convert(event.locationInWindow, from: nil)
        let imagePoint = viewPointToImagePoint(viewPoint)
        
        // Pass shift key state for constrained shapes
        let isShiftHeld = event.modifierFlags.contains(.shift)
        state.isShiftKeyHeld = isShiftHeld
        
        state.currentTool.mouseDragged(to: imagePoint, state: state)
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard let state = state else { return }
        
        let viewPoint = convert(event.locationInWindow, from: nil)
        let imagePoint = viewPointToImagePoint(viewPoint)
        
        state.currentTool.mouseUp(at: imagePoint, state: state)
        needsDisplay = true
    }
    
    override func mouseMoved(with event: NSEvent) {
        guard let state = state else { return }
        
        // Update cursor based on tool
        state.currentTool.cursor.set()
    }
    
    override func mouseEntered(with event: NSEvent) {
        guard let state = state else { return }
        state.currentTool.cursor.set()
    }
    
    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }
    
    // MARK: - Scroll Wheel (Zoom)

    override func scrollWheel(with event: NSEvent) {
        guard let state = state else {
            super.scrollWheel(with: event)
            return
        }

        // Pinch-to-zoom (trackpad) or Cmd+scroll
        if event.modifierFlags.contains(.command) || event.phase != [] || event.momentumPhase != [] {
            let delta = event.scrollingDeltaY
            if abs(delta) > 0.1 {
                let factor: CGFloat = 1.0 + delta * 0.01
                let newZoom = state.zoomLevel * factor
                state.setZoom(newZoom)
                needsDisplay = true
            }
            return
        }

        // Regular scroll: pan when zoomed in
        if state.zoomLevel > 1.0 + 0.01 {
            state.panOffset.x += event.scrollingDeltaX
            state.panOffset.y -= event.scrollingDeltaY
            needsDisplay = true
            return
        }

        super.scrollWheel(with: event)
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        guard let state = state else {
            super.keyDown(with: event)
            return
        }
        
        if !state.handleKeyDown(event) {
            super.keyDown(with: event)
        }
        needsDisplay = true
    }
    
    // MARK: - Refresh
    
    func refresh() {
        needsDisplay = true
    }

    func focusCanvas() {
        guard state?.editingTextAnnotationId == nil else { return }
        window?.makeFirstResponder(self)
    }
}

// MARK: - SwiftUI Wrapper

struct AnnotationCanvasRepresentable: NSViewRepresentable {
    @ObservedObject var state: AnnotationEditorState

    class Coordinator {
        var lastFocusRequestID: Int

        init(lastFocusRequestID: Int) {
            self.lastFocusRequestID = lastFocusRequestID
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(lastFocusRequestID: state.canvasFocusRequestID)
    }
    
    func makeNSView(context: Context) -> AnnotationCanvasView {
        let view = AnnotationCanvasView()
        view.state = state
        DispatchQueue.main.async {
            view.focusCanvas()
        }
        return view
    }
    
    func updateNSView(_ nsView: AnnotationCanvasView, context: Context) {
        nsView.state = state
        if context.coordinator.lastFocusRequestID != state.canvasFocusRequestID {
            context.coordinator.lastFocusRequestID = state.canvasFocusRequestID
            DispatchQueue.main.async {
                nsView.focusCanvas()
            }
        }
        nsView.refresh()
    }
}
