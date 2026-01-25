import AppKit
import SwiftUI

/// NSView that handles the annotation canvas rendering and mouse events
class AnnotationCanvasView: NSView {
    var state: AnnotationEditorState?
    private var trackingArea: NSTrackingArea?
    
    // Scale and offset for zooming/panning (future feature)
    var scale: CGFloat = 1.0
    var offset: CGPoint = .zero
    
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
    }
    
    private func imageRectInView() -> CGRect {
        guard let state = state else { return .zero }
        
        let imageSize = state.imageSize
        let viewSize = bounds.size
        
        // Fit image to view while maintaining aspect ratio
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height
        
        var scaledSize: CGSize
        if imageAspect > viewAspect {
            // Image is wider - fit to width
            scaledSize = CGSize(
                width: viewSize.width,
                height: viewSize.width / imageAspect
            )
        } else {
            // Image is taller - fit to height
            scaledSize = CGSize(
                width: viewSize.height * imageAspect,
                height: viewSize.height
            )
        }
        
        // Center in view
        let origin = CGPoint(
            x: (viewSize.width - scaledSize.width) / 2,
            y: (viewSize.height - scaledSize.height) / 2
        )
        
        // Update scale factor
        scale = scaledSize.width / imageSize.width
        
        return CGRect(origin: origin, size: scaledSize)
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
        let filter = CIFilter(name: "CIGaussianBlur")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(blur.blurRadius, forKey: kCIInputRadiusKey)
        
        if let outputImage = filter.outputImage {
            let ciContext = CIContext()
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
        
        let viewPoint = convert(event.locationInWindow, from: nil)
        let imagePoint = viewPointToImagePoint(viewPoint)
        
        // Check if within image bounds
        let imageBounds = CGRect(origin: .zero, size: state.imageSize)
        guard imageBounds.contains(imagePoint) else { return }
        
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
}

// MARK: - SwiftUI Wrapper

struct AnnotationCanvasRepresentable: NSViewRepresentable {
    @ObservedObject var state: AnnotationEditorState
    
    func makeNSView(context: Context) -> AnnotationCanvasView {
        let view = AnnotationCanvasView()
        view.state = state
        return view
    }
    
    func updateNSView(_ nsView: AnnotationCanvasView, context: Context) {
        nsView.state = state
        nsView.refresh()
    }
}
