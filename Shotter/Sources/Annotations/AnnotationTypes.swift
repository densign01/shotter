import AppKit
import Foundation

// MARK: - Arrow Annotation

struct ArrowAnnotation: Annotation {
    let id: AnnotationID
    var bounds: CGRect
    var isSelected: Bool = false
    var strokeColor: NSColor
    var strokeWidth: CGFloat
    var fillColor: NSColor?
    let createdAt: Date
    
    var startPoint: CGPoint
    var endPoint: CGPoint
    var headLength: CGFloat = 15
    var headAngle: CGFloat = .pi / 6  // 30 degrees
    
    init(
        start: CGPoint,
        end: CGPoint,
        strokeColor: NSColor = .systemRed,
        strokeWidth: CGFloat = 3
    ) {
        self.id = UUID()
        self.startPoint = start
        self.endPoint = end
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.fillColor = nil
        self.createdAt = Date()
        self.bounds = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).insetBy(dx: -headLength, dy: -headLength)
    }
    
    func render(in context: CGContext, scale: CGFloat) {
        context.saveGState()
        
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(strokeWidth * scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // Draw main line
        context.move(to: startPoint)
        context.addLine(to: endPoint)
        context.strokePath()
        
        // Draw arrowhead
        let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
        let scaledHeadLength = headLength * scale
        
        let arrowPoint1 = CGPoint(
            x: endPoint.x - scaledHeadLength * cos(angle - headAngle),
            y: endPoint.y - scaledHeadLength * sin(angle - headAngle)
        )
        let arrowPoint2 = CGPoint(
            x: endPoint.x - scaledHeadLength * cos(angle + headAngle),
            y: endPoint.y - scaledHeadLength * sin(angle + headAngle)
        )
        
        context.move(to: endPoint)
        context.addLine(to: arrowPoint1)
        context.move(to: endPoint)
        context.addLine(to: arrowPoint2)
        context.strokePath()
        
        context.restoreGState()
    }
    
    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool {
        // Check distance from point to line segment
        let distance = distanceFromPoint(point, toLineFrom: startPoint, to: endPoint)
        return distance <= tolerance + strokeWidth
    }
    
    private func distanceFromPoint(_ point: CGPoint, toLineFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        
        if lengthSquared == 0 {
            return hypot(point.x - start.x, point.y - start.y)
        }
        
        var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        
        let nearestX = start.x + t * dx
        let nearestY = start.y + t * dy
        
        return hypot(point.x - nearestX, point.y - nearestY)
    }
    
    func copy() -> any Annotation {
        var copy = self
        copy.isSelected = false
        return copy
    }
    
    mutating func updateBounds() {
        bounds = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        ).insetBy(dx: -headLength, dy: -headLength)
    }

    mutating func translate(by delta: CGPoint) {
        startPoint.x += delta.x
        startPoint.y += delta.y
        endPoint.x += delta.x
        endPoint.y += delta.y
        updateBounds()
    }

    /// Arrows don't support resize handles - only translation
    func resizeHandles() -> [ResizeHandle] {
        return []
    }

    static func == (lhs: ArrowAnnotation, rhs: ArrowAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Rectangle Annotation

struct RectangleAnnotation: Annotation {
    let id: AnnotationID
    var bounds: CGRect
    var isSelected: Bool = false
    var strokeColor: NSColor
    var strokeWidth: CGFloat
    var fillColor: NSColor?
    let createdAt: Date
    
    var cornerRadius: CGFloat = 0
    
    init(
        bounds: CGRect,
        strokeColor: NSColor = .systemRed,
        strokeWidth: CGFloat = 2,
        fillColor: NSColor? = nil,
        cornerRadius: CGFloat = 0
    ) {
        self.id = UUID()
        self.bounds = bounds
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.fillColor = fillColor
        self.cornerRadius = cornerRadius
        self.createdAt = Date()
    }
    
    func render(in context: CGContext, scale: CGFloat) {
        context.saveGState()
        
        let path: CGPath
        if cornerRadius > 0 {
            path = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        } else {
            path = CGPath(rect: bounds, transform: nil)
        }
        
        if let fill = fillColor {
            context.setFillColor(fill.cgColor)
            context.addPath(path)
            context.fillPath()
        }
        
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(strokeWidth * scale)
        context.addPath(path)
        context.strokePath()
        
        context.restoreGState()
    }
    
    func copy() -> any Annotation {
        var copy = self
        copy.isSelected = false
        return copy
    }
    
    static func == (lhs: RectangleAnnotation, rhs: RectangleAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Ellipse Annotation

struct EllipseAnnotation: Annotation {
    let id: AnnotationID
    var bounds: CGRect
    var isSelected: Bool = false
    var strokeColor: NSColor
    var strokeWidth: CGFloat
    var fillColor: NSColor?
    let createdAt: Date
    
    init(
        bounds: CGRect,
        strokeColor: NSColor = .systemRed,
        strokeWidth: CGFloat = 2,
        fillColor: NSColor? = nil
    ) {
        self.id = UUID()
        self.bounds = bounds
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.fillColor = fillColor
        self.createdAt = Date()
    }
    
    func render(in context: CGContext, scale: CGFloat) {
        context.saveGState()
        
        if let fill = fillColor {
            context.setFillColor(fill.cgColor)
            context.fillEllipse(in: bounds)
        }
        
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(strokeWidth * scale)
        context.strokeEllipse(in: bounds)
        
        context.restoreGState()
    }
    
    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool {
        // Check if point is near the ellipse perimeter or inside (if filled)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let a = bounds.width / 2
        let b = bounds.height / 2
        
        let normalizedX = (point.x - center.x) / a
        let normalizedY = (point.y - center.y) / b
        let distance = normalizedX * normalizedX + normalizedY * normalizedY
        
        if fillColor != nil {
            return distance <= 1.0
        } else {
            // Near the perimeter
            return abs(distance - 1.0) <= tolerance / min(a, b)
        }
    }
    
    func copy() -> any Annotation {
        var copy = self
        copy.isSelected = false
        return copy
    }
    
    static func == (lhs: EllipseAnnotation, rhs: EllipseAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Line Annotation

struct LineAnnotation: Annotation {
    let id: AnnotationID
    var bounds: CGRect
    var isSelected: Bool = false
    var strokeColor: NSColor
    var strokeWidth: CGFloat
    var fillColor: NSColor?
    let createdAt: Date
    
    var startPoint: CGPoint
    var endPoint: CGPoint
    
    init(
        start: CGPoint,
        end: CGPoint,
        strokeColor: NSColor = .systemRed,
        strokeWidth: CGFloat = 2
    ) {
        self.id = UUID()
        self.startPoint = start
        self.endPoint = end
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.fillColor = nil
        self.createdAt = Date()
        self.bounds = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
    
    func render(in context: CGContext, scale: CGFloat) {
        context.saveGState()
        
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(strokeWidth * scale)
        context.setLineCap(.round)
        
        context.move(to: startPoint)
        context.addLine(to: endPoint)
        context.strokePath()
        
        context.restoreGState()
    }
    
    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool {
        let distance = distanceFromPoint(point, toLineFrom: startPoint, to: endPoint)
        return distance <= tolerance + strokeWidth
    }
    
    private func distanceFromPoint(_ point: CGPoint, toLineFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        
        if lengthSquared == 0 {
            return hypot(point.x - start.x, point.y - start.y)
        }
        
        var t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        
        let nearestX = start.x + t * dx
        let nearestY = start.y + t * dy
        
        return hypot(point.x - nearestX, point.y - nearestY)
    }
    
    func copy() -> any Annotation {
        var copy = self
        copy.isSelected = false
        return copy
    }
    
    mutating func updateBounds() {
        bounds = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        )
    }

    mutating func translate(by delta: CGPoint) {
        startPoint.x += delta.x
        startPoint.y += delta.y
        endPoint.x += delta.x
        endPoint.y += delta.y
        updateBounds()
    }

    /// Lines don't support resize handles - only translation
    func resizeHandles() -> [ResizeHandle] {
        return []
    }

    static func == (lhs: LineAnnotation, rhs: LineAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Text Annotation

struct TextAnnotation: Annotation {
    let id: AnnotationID
    var bounds: CGRect
    var isSelected: Bool = false
    var strokeColor: NSColor
    var strokeWidth: CGFloat
    var fillColor: NSColor?
    let createdAt: Date
    
    var text: String
    var fontSize: CGFloat
    var fontName: String
    var backgroundColor: NSColor?
    
    init(
        position: CGPoint,
        text: String = "Text",
        strokeColor: NSColor = .white,
        fontSize: CGFloat = 16,
        fontName: String = "Helvetica Neue Bold",
        backgroundColor: NSColor? = .systemRed
    ) {
        self.id = UUID()
        self.text = text
        self.strokeColor = strokeColor
        self.strokeWidth = 0
        self.fillColor = nil
        self.fontSize = fontSize
        self.fontName = fontName
        self.backgroundColor = backgroundColor
        self.createdAt = Date()
        
        // Calculate initial bounds based on text size
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).size(withAttributes: attributes)
        
        self.bounds = CGRect(
            x: position.x,
            y: position.y - textSize.height,
            width: max(textSize.width + 16, 50),
            height: textSize.height + 8
        )
    }
    
    func render(in context: CGContext, scale: CGFloat) {
        context.saveGState()
        
        // Draw background if set
        if let bgColor = backgroundColor {
            context.setFillColor(bgColor.cgColor)
            let bgPath = CGPath(roundedRect: bounds, cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(bgPath)
            context.fillPath()
        }
        
        // Draw text
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: strokeColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        
        let textRect = CGRect(
            x: bounds.midX - textSize.width / 2,
            y: bounds.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        // Use NSGraphicsContext to draw text
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attributedString.draw(in: textRect)
        NSGraphicsContext.restoreGraphicsState()
        
        context.restoreGState()
    }
    
    mutating func updateBoundsForText() {
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).size(withAttributes: attributes)
        
        bounds = CGRect(
            x: bounds.origin.x,
            y: bounds.origin.y,
            width: max(textSize.width + 16, 50),
            height: textSize.height + 8
        )
    }
    
    func copy() -> any Annotation {
        var copy = self
        copy.isSelected = false
        return copy
    }
    
    static func == (lhs: TextAnnotation, rhs: TextAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Blur Annotation

struct BlurAnnotation: Annotation {
    let id: AnnotationID
    var bounds: CGRect
    var isSelected: Bool = false
    var strokeColor: NSColor
    var strokeWidth: CGFloat
    var fillColor: NSColor?
    let createdAt: Date
    
    var blurRadius: CGFloat
    
    init(
        bounds: CGRect,
        blurRadius: CGFloat = 10
    ) {
        self.id = UUID()
        self.bounds = bounds
        self.strokeColor = .clear
        self.strokeWidth = 0
        self.fillColor = nil
        self.blurRadius = blurRadius
        self.createdAt = Date()
    }
    
    func render(in context: CGContext, scale: CGFloat) {
        // Blur is applied differently - we need to blur the underlying image
        // This is handled specially in the canvas rendering
        context.saveGState()
        
        // Draw a subtle indicator when selected
        if isSelected {
            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 4])
            context.stroke(bounds)
        }
        
        context.restoreGState()
    }
    
    /// Apply blur to the specified region of an image
    func applyBlur(to image: NSImage) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIGaussianBlur") else {
            return nil
        }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(blurRadius, forKey: kCIInputRadiusKey)

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let context = CIContext()
        guard let blurredCGImage = context.createCGImage(outputImage, from: ciImage.extent) else {
            return nil
        }
        
        return NSImage(cgImage: blurredCGImage, size: image.size)
    }
    
    func copy() -> any Annotation {
        var copy = self
        copy.isSelected = false
        return copy
    }
    
    static func == (lhs: BlurAnnotation, rhs: BlurAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Counter Annotation

struct CounterAnnotation: Annotation {
    let id: AnnotationID
    var bounds: CGRect
    var isSelected: Bool = false
    var strokeColor: NSColor
    var strokeWidth: CGFloat
    var fillColor: NSColor?
    let createdAt: Date
    
    var number: Int
    var circleSize: CGFloat = 28
    
    init(
        center: CGPoint,
        number: Int,
        fillColor: NSColor = .systemRed,
        strokeColor: NSColor = .white
    ) {
        self.id = UUID()
        self.number = number
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeWidth = 0
        self.createdAt = Date()
        
        let halfSize = circleSize / 2
        self.bounds = CGRect(
            x: center.x - halfSize,
            y: center.y - halfSize,
            width: circleSize,
            height: circleSize
        )
    }
    
    func render(in context: CGContext, scale: CGFloat) {
        context.saveGState()
        
        // Draw filled circle
        if let fill = fillColor {
            context.setFillColor(fill.cgColor)
            context.fillEllipse(in: bounds)
        }
        
        // Draw number
        let font = NSFont.systemFont(ofSize: circleSize * 0.55, weight: .bold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: strokeColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let text = "\(number)"
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        
        let textRect = CGRect(
            x: bounds.midX - textSize.width / 2,
            y: bounds.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attributedString.draw(in: textRect)
        NSGraphicsContext.restoreGraphicsState()
        
        context.restoreGState()
    }
    
    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let distance = hypot(point.x - center.x, point.y - center.y)
        return distance <= circleSize / 2 + tolerance
    }
    
    func copy() -> any Annotation {
        var copy = self
        copy.isSelected = false
        return copy
    }
    
    static func == (lhs: CounterAnnotation, rhs: CounterAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Text Highlight Annotation

struct TextHighlightAnnotation: Annotation {
    let id: AnnotationID
    var bounds: CGRect
    var isSelected: Bool = false
    var strokeColor: NSColor
    var strokeWidth: CGFloat
    var fillColor: NSColor?
    let createdAt: Date

    /// Brush path points for the highlight stroke
    var brushPath: [CGPoint] = []

    /// Brush stroke width
    var brushWidth: CGFloat = 20

    /// Opacity for the highlight overlay (0.0 - 1.0)
    var highlightOpacity: CGFloat = 0.4

    init(fillColor: NSColor = .systemYellow, highlightOpacity: CGFloat = 0.4) {
        self.id = UUID()
        self.fillColor = fillColor
        self.highlightOpacity = highlightOpacity
        self.strokeColor = .clear
        self.strokeWidth = 0
        self.createdAt = Date()
        self.bounds = .zero
    }

    mutating func updateBounds() {
        guard !brushPath.isEmpty else {
            bounds = .zero
            return
        }

        let halfWidth = brushWidth / 2
        var minX = brushPath[0].x - halfWidth
        var minY = brushPath[0].y - halfWidth
        var maxX = brushPath[0].x + halfWidth
        var maxY = brushPath[0].y + halfWidth

        for point in brushPath {
            minX = min(minX, point.x - halfWidth)
            minY = min(minY, point.y - halfWidth)
            maxX = max(maxX, point.x + halfWidth)
            maxY = max(maxY, point.y + halfWidth)
        }

        bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func render(in context: CGContext, scale: CGFloat) {
        guard brushPath.count >= 2 else { return }

        context.saveGState()

        // Get highlight color with applied opacity
        let highlightColor: NSColor
        if let fill = fillColor {
            highlightColor = fill.withAlphaComponent(highlightOpacity)
        } else {
            highlightColor = NSColor.systemYellow.withAlphaComponent(highlightOpacity)
        }

        // Draw thick brush stroke
        context.setStrokeColor(highlightColor.cgColor)
        context.setLineWidth(brushWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.move(to: brushPath[0])
        for point in brushPath.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()

        context.restoreGState()
    }

    func hitTest(point: CGPoint, tolerance: CGFloat) -> Bool {
        // Early exit: check bounds first for performance
        guard bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else {
            return false
        }

        // Check if point is near any part of the brush path
        let hitDistance = brushWidth / 2 + tolerance
        for pathPoint in brushPath {
            let dx = point.x - pathPoint.x
            let dy = point.y - pathPoint.y
            if sqrt(dx * dx + dy * dy) < hitDistance {
                return true
            }
        }
        return false
    }

    func copy() -> any Annotation {
        var copy = self
        copy.isSelected = false
        return copy
    }

    mutating func translate(by delta: CGPoint) {
        brushPath = brushPath.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
        updateBounds()
    }

    func resizeHandles() -> [ResizeHandle] {
        return []
    }

    static func == (lhs: TextHighlightAnnotation, rhs: TextHighlightAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}
