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
    
    let baseImage: NSImage
    let imageSize: CGSize
    
    // MARK: - Current Tool
    
    private(set) var currentTool: AnnotationTool
    
    // MARK: - Initialization
    
    init(image: NSImage) {
        self.baseImage = image
        self.imageSize = image.size
        self.currentTool = AnnotationToolFactory.tool(for: .arrow)
    }
    
    // MARK: - Tool Management
    
    func setTool(_ type: AnnotationToolType) {
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
        
        var annotation = annotations[index].annotation
        annotation.bounds = bounds
        annotations[index] = AnyAnnotation(annotation)
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
            let filter = CIFilter(name: "CIGaussianBlur")!
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(blur.blurRadius, forKey: kCIInputRadiusKey)
            
            if let outputImage = filter.outputImage {
                let ciContext = CIContext()
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
            
            // Delete key
            if event.keyCode == 51 || event.keyCode == 117 { // Backspace or Delete
                deleteSelectedAnnotation()
                return true
            }
            
            // Escape
            if event.keyCode == 53 {
                selectAnnotation(nil)
                editingTextAnnotationId = nil
                return true
            }
        }
        
        return false
    }
}
