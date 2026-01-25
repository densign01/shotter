import AppKit
import SwiftUI

/// Unique identifier for annotations
typealias AnnotationID = UUID

/// Base protocol for all annotation types
protocol Annotation: Identifiable, Equatable {
    var id: AnnotationID { get }
    var bounds: CGRect { get set }
    var isSelected: Bool { get set }
    var strokeColor: NSColor { get set }
    var strokeWidth: CGFloat { get set }
    var fillColor: NSColor? { get set }
    var createdAt: Date { get }
    
    /// Render the annotation to the given graphics context
    func render(in context: CGContext, scale: CGFloat)
    
    /// Check if a point hits this annotation (for selection)
    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool
    
    /// Get resize handles for this annotation
    func resizeHandles() -> [ResizeHandle]
    
    /// Create a copy of this annotation
    func copy() -> any Annotation
}

/// Default implementations
extension Annotation {
    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool {
        let expandedBounds = bounds.insetBy(dx: -tolerance, dy: -tolerance)
        return expandedBounds.contains(point)
    }
    
    func resizeHandles() -> [ResizeHandle] {
        return ResizeHandle.standardHandles(for: bounds)
    }
}

/// Resize handle positions
enum ResizeHandlePosition: CaseIterable {
    case topLeft, topCenter, topRight
    case middleLeft, middleRight
    case bottomLeft, bottomCenter, bottomRight
}

/// A resize handle for annotations
struct ResizeHandle {
    let position: ResizeHandlePosition
    let rect: CGRect
    
    static let handleSize: CGFloat = 8
    
    static func standardHandles(for bounds: CGRect) -> [ResizeHandle] {
        let size = handleSize
        let half = size / 2
        
        return ResizeHandlePosition.allCases.map { position in
            let point: CGPoint
            switch position {
            case .topLeft: point = CGPoint(x: bounds.minX, y: bounds.maxY)
            case .topCenter: point = CGPoint(x: bounds.midX, y: bounds.maxY)
            case .topRight: point = CGPoint(x: bounds.maxX, y: bounds.maxY)
            case .middleLeft: point = CGPoint(x: bounds.minX, y: bounds.midY)
            case .middleRight: point = CGPoint(x: bounds.maxX, y: bounds.midY)
            case .bottomLeft: point = CGPoint(x: bounds.minX, y: bounds.minY)
            case .bottomCenter: point = CGPoint(x: bounds.midX, y: bounds.minY)
            case .bottomRight: point = CGPoint(x: bounds.maxX, y: bounds.minY)
            }
            
            return ResizeHandle(
                position: position,
                rect: CGRect(x: point.x - half, y: point.y - half, width: size, height: size)
            )
        }
    }
}

/// Wrapper to store any annotation in a type-erased way
struct AnyAnnotation: Identifiable, Equatable {
    let id: AnnotationID
    private let _annotation: any Annotation
    
    var annotation: any Annotation { _annotation }
    
    init(_ annotation: any Annotation) {
        self.id = annotation.id
        self._annotation = annotation
    }
    
    static func == (lhs: AnyAnnotation, rhs: AnyAnnotation) -> Bool {
        lhs.id == rhs.id
    }
    
    var bounds: CGRect {
        get { _annotation.bounds }
    }
    
    var isSelected: Bool {
        get { _annotation.isSelected }
    }
}
