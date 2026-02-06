import AppKit
import SwiftUI

/// Available annotation tool types
enum AnnotationToolType: String, CaseIterable, Identifiable {
    case select = "Select"
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case line = "Line"
    case text = "Text"
    case blur = "Blur"
    case counter = "Counter"
    case eraser = "Eraser"
    case crop = "Crop"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .text: return "textformat"
        case .blur: return "drop.halffull"
        case .counter: return "number.circle"
        case .eraser: return "eraser"
        case .crop: return "crop"
        }
    }
    
    var tooltip: String {
        switch self {
        case .select: return "Select and move annotations (V)"
        case .arrow: return "Draw arrow (A)"
        case .rectangle: return "Draw rectangle (R)"
        case .ellipse: return "Draw ellipse/circle (E)"
        case .line: return "Draw line (L)"
        case .text: return "Add text (T)"
        case .blur: return "Blur region (B)"
        case .counter: return "Add numbered counter (C)"
        case .eraser: return "Click annotation to remove (X)"
        case .crop: return "Crop screenshot"
        }
    }
    
    var shortcut: Character? {
        switch self {
        case .select: return "v"
        case .arrow: return "a"
        case .rectangle: return "r"
        case .ellipse: return "e"
        case .line: return "l"
        case .text: return "t"
        case .blur: return "b"
        case .counter: return "c"
        case .eraser: return "x"
        case .crop: return nil
        }
    }
}

/// Protocol for annotation tools
protocol AnnotationTool {
    var toolType: AnnotationToolType { get }
    
    /// Called when mouse is pressed
    func mouseDown(at point: CGPoint, state: AnnotationEditorState)
    
    /// Called when mouse is dragged
    func mouseDragged(to point: CGPoint, state: AnnotationEditorState)
    
    /// Called when mouse is released
    func mouseUp(at point: CGPoint, state: AnnotationEditorState)
    
    /// Get the cursor for this tool
    var cursor: NSCursor { get }
}

/// Default cursor implementation
extension AnnotationTool {
    var cursor: NSCursor { .crosshair }
}

// MARK: - Select Tool

class SelectTool: AnnotationTool {
    let toolType: AnnotationToolType = .select
    var cursor: NSCursor { .arrow }
    
    private var dragStartPoint: CGPoint?
    private var originalBounds: CGRect?
    private var draggedAnnotationId: AnnotationID?
    private var resizingHandle: ResizeHandlePosition?
    
    func mouseDown(at point: CGPoint, state: AnnotationEditorState) {
        dragStartPoint = point
        
        // Check if clicking on a resize handle of selected annotation
        if let selectedId = state.selectedAnnotationId,
           let annotation = state.annotations.first(where: { $0.id == selectedId }) {
            for handle in annotation.annotation.resizeHandles() {
                if handle.rect.contains(point) {
                    resizingHandle = handle.position
                    originalBounds = annotation.bounds
                    draggedAnnotationId = selectedId
                    return
                }
            }
        }
        
        // Check if clicking on an annotation
        for annotation in state.annotations.reversed() {
            if annotation.annotation.hitTest(point: point, tolerance: 5) {
                state.selectAnnotation(annotation.id)
                draggedAnnotationId = annotation.id
                originalBounds = annotation.bounds
                return
            }
        }
        
        // Clicked on empty space - deselect
        state.selectAnnotation(nil)
        draggedAnnotationId = nil
    }
    
    func mouseDragged(to point: CGPoint, state: AnnotationEditorState) {
        guard let startPoint = dragStartPoint,
              let annotationId = draggedAnnotationId,
              let originalBounds = originalBounds else { return }
        
        let dx = point.x - startPoint.x
        let dy = point.y - startPoint.y
        
        if let handlePos = resizingHandle {
            // Resizing
            var newBounds = originalBounds
            
            switch handlePos {
            case .topLeft:
                newBounds.origin.x = originalBounds.origin.x + dx
                newBounds.size.width = originalBounds.width - dx
                newBounds.size.height = originalBounds.height + dy
            case .topCenter:
                newBounds.size.height = originalBounds.height + dy
            case .topRight:
                newBounds.size.width = originalBounds.width + dx
                newBounds.size.height = originalBounds.height + dy
            case .middleLeft:
                newBounds.origin.x = originalBounds.origin.x + dx
                newBounds.size.width = originalBounds.width - dx
            case .middleRight:
                newBounds.size.width = originalBounds.width + dx
            case .bottomLeft:
                newBounds.origin.x = originalBounds.origin.x + dx
                newBounds.origin.y = originalBounds.origin.y + dy
                newBounds.size.width = originalBounds.width - dx
                newBounds.size.height = originalBounds.height - dy
            case .bottomCenter:
                newBounds.origin.y = originalBounds.origin.y + dy
                newBounds.size.height = originalBounds.height - dy
            case .bottomRight:
                newBounds.origin.y = originalBounds.origin.y + dy
                newBounds.size.width = originalBounds.width + dx
                newBounds.size.height = originalBounds.height - dy
            }
            
            // Ensure minimum size
            if newBounds.width >= 10 && newBounds.height >= 10 {
                state.updateAnnotationBounds(annotationId, bounds: newBounds)
            }
        } else {
            // Moving
            let newBounds = CGRect(
                x: originalBounds.origin.x + dx,
                y: originalBounds.origin.y + dy,
                width: originalBounds.width,
                height: originalBounds.height
            )
            state.updateAnnotationBounds(annotationId, bounds: newBounds)
        }
    }
    
    func mouseUp(at point: CGPoint, state: AnnotationEditorState) {
        dragStartPoint = nil
        originalBounds = nil
        draggedAnnotationId = nil
        resizingHandle = nil
    }
}

// MARK: - Arrow Tool

class ArrowTool: AnnotationTool {
    let toolType: AnnotationToolType = .arrow
    
    private var startPoint: CGPoint?
    private var currentAnnotation: ArrowAnnotation?
    
    func mouseDown(at point: CGPoint, state: AnnotationEditorState) {
        startPoint = point
        
        var annotation = ArrowAnnotation(
            start: point,
            end: point,
            strokeColor: state.currentColor,
            strokeWidth: state.strokeWidth
        )
        annotation.isSelected = true
        currentAnnotation = annotation
        state.addAnnotation(annotation)
        state.selectAnnotation(annotation.id)
    }
    
    func mouseDragged(to point: CGPoint, state: AnnotationEditorState) {
        guard var annotation = currentAnnotation else { return }
        annotation.endPoint = point
        annotation.updateBounds()
        state.updateAnnotation(annotation)
        currentAnnotation = annotation
    }
    
    func mouseUp(at point: CGPoint, state: AnnotationEditorState) {
        guard var annotation = currentAnnotation else { return }
        
        // If start and end are too close, remove the annotation
        let distance = hypot(point.x - annotation.startPoint.x, point.y - annotation.startPoint.y)
        if distance < 5 {
            state.removeAnnotation(annotation.id)
        } else {
            annotation.isSelected = false
            state.updateAnnotation(annotation)
        }
        
        startPoint = nil
        currentAnnotation = nil
    }
}

// MARK: - Rectangle Tool

class RectangleTool: AnnotationTool {
    let toolType: AnnotationToolType = .rectangle
    
    private var startPoint: CGPoint?
    private var currentAnnotation: RectangleAnnotation?
    
    func mouseDown(at point: CGPoint, state: AnnotationEditorState) {
        startPoint = point
        
        var annotation = RectangleAnnotation(
            bounds: CGRect(origin: point, size: .zero),
            strokeColor: state.currentColor,
            strokeWidth: state.strokeWidth,
            fillColor: state.fillEnabled ? state.currentColor.withAlphaComponent(0.3) : nil
        )
        annotation.isSelected = true
        currentAnnotation = annotation
        state.addAnnotation(annotation)
        state.selectAnnotation(annotation.id)
    }
    
    func mouseDragged(to point: CGPoint, state: AnnotationEditorState) {
        guard var annotation = currentAnnotation, let start = startPoint else { return }
        
        var width = abs(point.x - start.x)
        var height = abs(point.y - start.y)
        
        // Constrain to square if shift is held
        if state.isShiftKeyHeld {
            let size = max(width, height)
            width = size
            height = size
        }
        
        let bounds = CGRect(
            x: point.x < start.x ? start.x - width : start.x,
            y: point.y < start.y ? start.y - height : start.y,
            width: width,
            height: height
        )
        annotation.bounds = bounds
        state.updateAnnotation(annotation)
        currentAnnotation = annotation
    }
    
    func mouseUp(at point: CGPoint, state: AnnotationEditorState) {
        guard var annotation = currentAnnotation else { return }
        
        // If too small, remove
        if annotation.bounds.width < 5 || annotation.bounds.height < 5 {
            state.removeAnnotation(annotation.id)
        } else {
            annotation.isSelected = false
            state.updateAnnotation(annotation)
        }
        
        startPoint = nil
        currentAnnotation = nil
    }
}

// MARK: - Ellipse Tool

class EllipseTool: AnnotationTool {
    let toolType: AnnotationToolType = .ellipse
    
    private var startPoint: CGPoint?
    private var currentAnnotation: EllipseAnnotation?
    
    func mouseDown(at point: CGPoint, state: AnnotationEditorState) {
        startPoint = point
        
        var annotation = EllipseAnnotation(
            bounds: CGRect(origin: point, size: .zero),
            strokeColor: state.currentColor,
            strokeWidth: state.strokeWidth,
            fillColor: state.fillEnabled ? state.currentColor.withAlphaComponent(0.3) : nil
        )
        annotation.isSelected = true
        currentAnnotation = annotation
        state.addAnnotation(annotation)
        state.selectAnnotation(annotation.id)
    }
    
    func mouseDragged(to point: CGPoint, state: AnnotationEditorState) {
        guard var annotation = currentAnnotation, let start = startPoint else { return }
        
        var width = abs(point.x - start.x)
        var height = abs(point.y - start.y)
        
        // Constrain to circle if shift is held
        if state.isShiftKeyHeld {
            let size = max(width, height)
            width = size
            height = size
        }
        
        let bounds = CGRect(
            x: point.x < start.x ? start.x - width : start.x,
            y: point.y < start.y ? start.y - height : start.y,
            width: width,
            height: height
        )
        annotation.bounds = bounds
        state.updateAnnotation(annotation)
        currentAnnotation = annotation
    }
    
    func mouseUp(at point: CGPoint, state: AnnotationEditorState) {
        guard var annotation = currentAnnotation else { return }
        
        if annotation.bounds.width < 5 || annotation.bounds.height < 5 {
            state.removeAnnotation(annotation.id)
        } else {
            annotation.isSelected = false
            state.updateAnnotation(annotation)
        }
        
        startPoint = nil
        currentAnnotation = nil
    }
}

// MARK: - Line Tool

class LineTool: AnnotationTool {
    let toolType: AnnotationToolType = .line
    
    private var startPoint: CGPoint?
    private var currentAnnotation: LineAnnotation?
    
    func mouseDown(at point: CGPoint, state: AnnotationEditorState) {
        startPoint = point
        
        var annotation = LineAnnotation(
            start: point,
            end: point,
            strokeColor: state.currentColor,
            strokeWidth: state.strokeWidth
        )
        annotation.isSelected = true
        currentAnnotation = annotation
        state.addAnnotation(annotation)
        state.selectAnnotation(annotation.id)
    }
    
    func mouseDragged(to point: CGPoint, state: AnnotationEditorState) {
        guard var annotation = currentAnnotation else { return }
        annotation.endPoint = point
        annotation.updateBounds()
        state.updateAnnotation(annotation)
        currentAnnotation = annotation
    }
    
    func mouseUp(at point: CGPoint, state: AnnotationEditorState) {
        guard var annotation = currentAnnotation else { return }
        
        let distance = hypot(point.x - annotation.startPoint.x, point.y - annotation.startPoint.y)
        if distance < 5 {
            state.removeAnnotation(annotation.id)
        } else {
            annotation.isSelected = false
            state.updateAnnotation(annotation)
        }
        
        startPoint = nil
        currentAnnotation = nil
    }
}

// MARK: - Text Tool

class TextTool: AnnotationTool {
    let toolType: AnnotationToolType = .text
    var cursor: NSCursor { .iBeam }
    
    func mouseDown(at point: CGPoint, state: AnnotationEditorState) {
        // Create text annotation at click point
        var annotation = TextAnnotation(
            position: point,
            text: "Text",
            strokeColor: .white,
            fontSize: state.fontSize,
            backgroundColor: state.currentColor
        )
        annotation.isSelected = true
        state.addAnnotation(annotation)
        state.selectAnnotation(annotation.id)
        
        // Notify to show text editor
        state.editingTextAnnotationId = annotation.id
    }
    
    func mouseDragged(to point: CGPoint, state: AnnotationEditorState) {
        // Text tool doesn't drag
    }
    
    func mouseUp(at point: CGPoint, state: AnnotationEditorState) {
        // Nothing to do
    }
}

// MARK: - Blur Tool

class BlurTool: AnnotationTool {
    let toolType: AnnotationToolType = .blur
    
    private var startPoint: CGPoint?
    private var currentAnnotation: BlurAnnotation?
    
    func mouseDown(at point: CGPoint, state: AnnotationEditorState) {
        startPoint = point
        
        var annotation = BlurAnnotation(
            bounds: CGRect(origin: point, size: .zero),
            blurRadius: 15
        )
        annotation.isSelected = true
        currentAnnotation = annotation
        state.addAnnotation(annotation)
        state.selectAnnotation(annotation.id)
    }
    
    func mouseDragged(to point: CGPoint, state: AnnotationEditorState) {
        guard var annotation = currentAnnotation, let start = startPoint else { return }
        
        let bounds = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
        annotation.bounds = bounds
        state.updateAnnotation(annotation)
        currentAnnotation = annotation
    }
    
    func mouseUp(at point: CGPoint, state: AnnotationEditorState) {
        guard var annotation = currentAnnotation else { return }
        
        if annotation.bounds.width < 10 || annotation.bounds.height < 10 {
            state.removeAnnotation(annotation.id)
        } else {
            annotation.isSelected = false
            state.updateAnnotation(annotation)
        }
        
        startPoint = nil
        currentAnnotation = nil
    }
}

// MARK: - Counter Tool

class CounterTool: AnnotationTool {
    let toolType: AnnotationToolType = .counter
    
    func mouseDown(at point: CGPoint, state: AnnotationEditorState) {
        let nextNumber = state.nextCounterNumber
        
        var annotation = CounterAnnotation(
            center: point,
            number: nextNumber,
            fillColor: state.currentColor,
            strokeColor: .white
        )
        annotation.isSelected = true
        state.addAnnotation(annotation)
        state.selectAnnotation(annotation.id)
        state.nextCounterNumber = nextNumber + 1
    }
    
    func mouseDragged(to point: CGPoint, state: AnnotationEditorState) {
        // Counter doesn't drag on creation
    }
    
    func mouseUp(at point: CGPoint, state: AnnotationEditorState) {
        if let selectedId = state.selectedAnnotationId {
            state.deselectAnnotation(selectedId)
        }
    }
}

// MARK: - Eraser Tool

class EraserTool: AnnotationTool {
    let toolType: AnnotationToolType = .eraser
    var cursor: NSCursor { .disappearingItem }

    func mouseDown(at point: CGPoint, state: AnnotationEditorState) {
        // Find the topmost annotation under the click and remove it
        for annotation in state.annotations.reversed() {
            if annotation.annotation.hitTest(point: point, tolerance: 5) {
                state.removeAnnotation(annotation.id)
                return
            }
        }
    }

    func mouseDragged(to point: CGPoint, state: AnnotationEditorState) {
        // Eraser doesn't drag
    }

    func mouseUp(at point: CGPoint, state: AnnotationEditorState) {
        // Nothing to do
    }
}

// MARK: - Crop Tool

class CropTool: AnnotationTool {
    let toolType: AnnotationToolType = .crop
    var cursor: NSCursor { .crosshair }

    private var startPoint: CGPoint?

    func mouseDown(at point: CGPoint, state: AnnotationEditorState) {
        startPoint = point
        state.cropRect = CGRect(origin: point, size: .zero)
    }

    func mouseDragged(to point: CGPoint, state: AnnotationEditorState) {
        guard let start = startPoint else { return }
        state.cropRect = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        )
    }

    func mouseUp(at point: CGPoint, state: AnnotationEditorState) {
        // If crop rect is too small, cancel
        if let rect = state.cropRect, rect.width < 10 || rect.height < 10 {
            state.cropRect = nil
        }
        startPoint = nil
    }
}

// MARK: - Tool Factory

struct AnnotationToolFactory {
    static func tool(for type: AnnotationToolType) -> AnnotationTool {
        switch type {
        case .select: return SelectTool()
        case .arrow: return ArrowTool()
        case .rectangle: return RectangleTool()
        case .ellipse: return EllipseTool()
        case .line: return LineTool()
        case .text: return TextTool()
        case .blur: return BlurTool()
        case .counter: return CounterTool()
        case .eraser: return EraserTool()
        case .crop: return CropTool()
        }
    }
}
