import AppKit
import SwiftUI
import Combine

/// Manages the state of the annotation editor
class AnnotationEditorState: ObservableObject {
    // MARK: - Published Properties
    
    @Published var annotations: [AnyAnnotation] = []
    @Published var selectedAnnotationId: AnnotationID?
    @Published var currentToolType: AnnotationToolType = .arrow
    @Published var currentColor: NSColor = .systemRed
    @Published var strokeWidth: CGFloat = 3
    @Published var fillEnabled: Bool = false
    @Published var fontSize: CGFloat = 16
    @Published var editingTextAnnotationId: AnnotationID?
    @Published var nextCounterNumber: Int = 1
    @Published var cropRect: CGRect? = nil
    @Published private(set) var canvasFocusRequestID: Int = 0
    @Published var zoomLevel: CGFloat = 1.0 // 1.0 = fit to window
    @Published var scrollOffset: CGPoint = .zero

    // Modifier keys
    var isShiftKeyHeld: Bool = false
    
    // Recent colors
    @Published var recentColors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow,
        .systemGreen, .systemBlue, .systemPurple
    ]
    
    // MARK: - Undo/Redo
    
    private var undoStack: [[AnyAnnotation]] = []
    private var redoStack: [[AnyAnnotation]] = []
    private let maxUndoLevels = 50
    
    // MARK: - Base Image

    private(set) var baseImage: NSImage
    private(set) var imageSize: CGSize
    private(set) var hasBeenCropped: Bool = false

    /// Whether the editor has changes worth prompting about on close
    var hasUnsavedChanges: Bool {
        !annotations.isEmpty || hasBeenCropped
    }

    // Cached CIContext for blur operations (expensive to create)
    private let ciContext = CIContext()
    
    // MARK: - Current Tool
    
    private(set) var currentTool: AnnotationTool
    
    // MARK: - Initialization
    
    init(image: NSImage) {
        self.baseImage = image
        self.imageSize = image.size
        self.currentTool = AnnotationToolFactory.tool(for: .arrow)
    }
    
    // MARK: - Zoom

    static let zoomPresets: [CGFloat] = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0]

    func zoomIn() {
        let nextLevel = Self.zoomPresets.first(where: { $0 > zoomLevel }) ?? zoomLevel
        zoomLevel = nextLevel
    }

    func zoomOut() {
        let prevLevel = Self.zoomPresets.last(where: { $0 < zoomLevel }) ?? zoomLevel
        zoomLevel = prevLevel
    }

    func zoomToFit() {
        zoomLevel = 1.0
        scrollOffset = .zero
    }

    var zoomPercentage: Int {
        Int(round(zoomLevel * 100))
    }

    // MARK: - Tool Management
    
    func setTool(_ type: AnnotationToolType) {
        // If switching away from crop tool with an active crop rect, clear it
        if currentToolType == .crop && type != .crop && cropRect != nil {
            cropRect = nil
        }

        currentToolType = type
        currentTool = AnnotationToolFactory.tool(for: type)

        // Deselect when changing tools (except select tool)
        if type != .select {
            selectAnnotation(nil)
        }

    }
    
    // MARK: - Annotation Management
    
    func addAnnotation(_ annotation: any Annotation) {
        saveUndoState()
        annotations.append(AnyAnnotation(annotation))
    }
    
    func updateAnnotation(_ annotation: any Annotation) {
        if let index = annotations.firstIndex(where: { $0.id == annotation.id }) {
            annotations[index] = AnyAnnotation(annotation)
        }
    }
    
    func updateAnnotationBounds(_ id: AnnotationID, bounds: CGRect) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }

        let annotation = annotations[index].annotation

        // For point-based annotations (arrows/lines), translate the endpoints
        if var arrow = annotation as? ArrowAnnotation {
            let delta = CGPoint(
                x: bounds.origin.x - arrow.bounds.origin.x,
                y: bounds.origin.y - arrow.bounds.origin.y
            )
            arrow.translate(by: delta)
            annotations[index] = AnyAnnotation(arrow)
        } else if var line = annotation as? LineAnnotation {
            let delta = CGPoint(
                x: bounds.origin.x - line.bounds.origin.x,
                y: bounds.origin.y - line.bounds.origin.y
            )
            line.translate(by: delta)
            annotations[index] = AnyAnnotation(line)
        } else if var highlight = annotation as? TextHighlightAnnotation {
            let delta = CGPoint(
                x: bounds.origin.x - highlight.bounds.origin.x,
                y: bounds.origin.y - highlight.bounds.origin.y
            )
            highlight.translate(by: delta)
            annotations[index] = AnyAnnotation(highlight)
        } else {
            var mutableAnnotation = annotation
            mutableAnnotation.bounds = bounds
            annotations[index] = AnyAnnotation(mutableAnnotation)
        }
    }
    
    func removeAnnotation(_ id: AnnotationID) {
        saveUndoState()
        annotations.removeAll { $0.id == id }
        if selectedAnnotationId == id {
            selectedAnnotationId = nil
        }
    }
    
    func selectAnnotation(_ id: AnnotationID?) {
        // Deselect previous
        if let prevId = selectedAnnotationId,
           let index = annotations.firstIndex(where: { $0.id == prevId }) {
            var annotation = annotations[index].annotation
            annotation.isSelected = false
            annotations[index] = AnyAnnotation(annotation)
        }
        
        selectedAnnotationId = id
        
        // Select new
        if let newId = id,
           let index = annotations.firstIndex(where: { $0.id == newId }) {
            var annotation = annotations[index].annotation
            annotation.isSelected = true
            annotations[index] = AnyAnnotation(annotation)
        }
    }
    
    func deselectAnnotation(_ id: AnnotationID) {
        if selectedAnnotationId == id {
            selectedAnnotationId = nil
        }
        if let index = annotations.firstIndex(where: { $0.id == id }) {
            var annotation = annotations[index].annotation
            annotation.isSelected = false
            annotations[index] = AnyAnnotation(annotation)
        }
    }
    
    func deleteSelectedAnnotation() {
        if let id = selectedAnnotationId {
            removeAnnotation(id)
        }
    }
    
    // MARK: - Color Management
    
    func setColor(_ color: NSColor) {
        currentColor = color
        addToRecentColors(color)
    }
    
    private func addToRecentColors(_ color: NSColor) {
        // Remove if already exists
        recentColors.removeAll { $0 == color }
        // Add to front
        recentColors.insert(color, at: 0)
        // Keep only last 6
        if recentColors.count > 6 {
            recentColors = Array(recentColors.prefix(6))
        }
    }
    
    // MARK: - Undo/Redo
    
    private func saveUndoState() {
        undoStack.append(annotations)
        if undoStack.count > maxUndoLevels {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    func saveUndoCheckpoint() {
        saveUndoState()
    }
    
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    
    func undo() {
        guard let previousState = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previousState
        selectedAnnotationId = nil
    }
    
    func redo() {
        guard let nextState = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = nextState
        selectedAnnotationId = nil
    }
    
    // MARK: - Text Editing
    
    func updateTextAnnotation(id: AnnotationID, text: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id }),
              var textAnnotation = annotations[index].annotation as? TextAnnotation else { return }
        
        saveUndoState()
        textAnnotation.text = text
        textAnnotation.updateBoundsForText()
        annotations[index] = AnyAnnotation(textAnnotation)
    }
    
    func finishTextEditing() {
        editingTextAnnotationId = nil
        requestCanvasFocus()
    }

    func requestCanvasFocus() {
        canvasFocusRequestID &+= 1
    }
    
    // MARK: - Crop

    func applyCrop() {
        guard let crop = cropRect else { return }

        // Clamp crop rect to image bounds
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let clampedCrop = crop.intersection(imageBounds)
        guard !clampedCrop.isNull && clampedCrop.width > 1 && clampedCrop.height > 1 else {
            cropRect = nil
            return
        }

        // Create cropped image via CGImage to preserve Retina pixel density
        let newSize = clampedCrop.size
        guard let cgImage = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            cropRect = nil
            return
        }

        let scaleX = CGFloat(cgImage.width) / imageSize.width
        let scaleY = CGFloat(cgImage.height) / imageSize.height
        let pixelCrop = CGRect(
            x: clampedCrop.origin.x * scaleX,
            y: (imageSize.height - clampedCrop.maxY) * scaleY,
            width: clampedCrop.width * scaleX,
            height: clampedCrop.height * scaleY
        ).integral
        let pixelBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let clampedPixelCrop = pixelCrop.intersection(pixelBounds)

        guard !clampedPixelCrop.isNull,
              clampedPixelCrop.width > 1,
              clampedPixelCrop.height > 1,
              let croppedCG = cgImage.cropping(to: clampedPixelCrop) else {
            cropRect = nil
            return
        }

        let croppedImage = NSImage(cgImage: croppedCG, size: newSize)

        // Offset all annotations by subtracting crop origin
        let offsetX = -clampedCrop.origin.x
        let offsetY = -clampedCrop.origin.y
        let newImageBounds = CGRect(origin: .zero, size: newSize)

        var updatedAnnotations: [AnyAnnotation] = []
        for anyAnnotation in annotations {
            var annotation = anyAnnotation.annotation

            if var arrow = annotation as? ArrowAnnotation {
                arrow.translate(by: CGPoint(x: offsetX, y: offsetY))
                // Check if still within new image bounds
                if arrow.bounds.intersects(newImageBounds) {
                    updatedAnnotations.append(AnyAnnotation(arrow))
                }
            } else if var line = annotation as? LineAnnotation {
                line.translate(by: CGPoint(x: offsetX, y: offsetY))
                if line.bounds.intersects(newImageBounds) {
                    updatedAnnotations.append(AnyAnnotation(line))
                }
            } else if var highlight = annotation as? TextHighlightAnnotation {
                highlight.translate(by: CGPoint(x: offsetX, y: offsetY))
                if highlight.bounds.intersects(newImageBounds) {
                    updatedAnnotations.append(AnyAnnotation(highlight))
                }
            } else {
                annotation.bounds = CGRect(
                    x: annotation.bounds.origin.x + offsetX,
                    y: annotation.bounds.origin.y + offsetY,
                    width: annotation.bounds.width,
                    height: annotation.bounds.height
                )
                if annotation.bounds.intersects(newImageBounds) {
                    updatedAnnotations.append(AnyAnnotation(annotation))
                }
            }
        }

        // Apply changes
        baseImage = croppedImage
        imageSize = newSize
        hasBeenCropped = true
        annotations = updatedAnnotations
        selectedAnnotationId = nil
        cropRect = nil
        undoStack.removeAll()
        redoStack.removeAll()
        setTool(.select)
    }

    func cancelCrop() {
        cropRect = nil
        setTool(.select)
    }

    // MARK: - Rendering
    
    /// Render the final image with all annotations
    func renderFinalImage() -> NSImage? {
        let size = baseImage.size
        
        let image = NSImage(size: size)
        image.lockFocus()
        
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return nil
        }
        
        // Draw base image
        baseImage.draw(in: CGRect(origin: .zero, size: size))
        
        // Apply blur annotations first (they affect the base image)
        for anyAnnotation in annotations {
            if let blurAnnotation = anyAnnotation.annotation as? BlurAnnotation {
                applyBlur(blurAnnotation, in: context, imageSize: size)
            }
        }
        
        // Draw other annotations
        for anyAnnotation in annotations {
            if !(anyAnnotation.annotation is BlurAnnotation) {
                anyAnnotation.annotation.render(in: context, scale: 1.0)
            }
        }
        
        image.unlockFocus()
        return image
    }
    
    private func applyBlur(_ blur: BlurAnnotation, in context: CGContext, imageSize: CGSize) {
        // Clip to blur bounds
        context.saveGState()
        context.clip(to: blur.bounds)

        // Create blurred version of the region
        if let cgImage = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let ciImage = CIImage(cgImage: cgImage)
            guard let filter = CIFilter(name: "CIGaussianBlur") else {
                context.restoreGState()
                return
            }
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(blur.blurRadius, forKey: kCIInputRadiusKey)

            if let outputImage = filter.outputImage {
                if let blurredCGImage = ciContext.createCGImage(outputImage, from: ciImage.extent) {
                    // Draw the blurred image in the clipped region
                    context.draw(blurredCGImage, in: CGRect(origin: .zero, size: imageSize))
                }
            }
        }

        context.restoreGState()
    }
}

// MARK: - Keyboard Shortcuts

extension AnnotationEditorState {
    func handleKeyDown(_ event: NSEvent) -> Bool {
        // Check for modifier keys
        let hasCommand = event.modifierFlags.contains(.command)
        let hasShift = event.modifierFlags.contains(.shift)
        
        // Handle shortcuts
        if hasCommand && hasShift {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "z":
                redo()
                return true
            case "c":
                // Copy to clipboard handled by window
                return false
            default:
                break
            }
        } else if hasCommand {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "z":
                undo()
                return true
            case "s":
                // Save handled by window
                return false
            case "a":
                // Select all - select first annotation if none selected
                if selectedAnnotationId == nil, let first = annotations.first {
                    selectAnnotation(first.id)
                }
                return true
            case "=", "+":
                zoomIn()
                return true
            case "-":
                zoomOut()
                return true
            case "0":
                zoomToFit()
                return true
            default:
                break
            }
        } else {
            // Tool shortcuts
            if let char = event.charactersIgnoringModifiers?.lowercased().first {
                for tool in AnnotationToolType.allCases {
                    if tool.shortcut == char {
                        setTool(tool)
                        return true
                    }
                }
            }
            
            // Enter/Return to confirm crop
            if (event.keyCode == 36 || event.keyCode == 76) && cropRect != nil {
                applyCrop()
                return true
            }

            // Delete key
            if event.keyCode == 51 || event.keyCode == 117 { // Backspace or Delete
                deleteSelectedAnnotation()
                return true
            }

            // Escape - cancel crop if active, otherwise normal deselect
            if event.keyCode == 53 {
                if cropRect != nil {
                    cancelCrop()
                    return true
                }
                selectAnnotation(nil)
                editingTextAnnotationId = nil
                return true
            }
        }
        
        return false
    }
}
