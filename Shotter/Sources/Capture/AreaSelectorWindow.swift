import AppKit

class AreaSelectorWindow: NSWindow {
    private var selectionView: AreaSelectionView?
    private var completion: ((CGRect?) -> Void)?
    
    init(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
        
        // Get the main screen frame
        guard let screen = NSScreen.main else {
            super.init(
                contentRect: .zero,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            completion(nil)
            return
        }
        
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        
        // Configure window
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hasShadow = false
        
        // Create selection view
        let view = AreaSelectionView(frame: screen.frame)
        view.onSelectionComplete = { [weak self] rect in
            self?.handleSelectionComplete(rect)
        }
        view.onCancel = { [weak self] in
            self?.handleCancel()
        }
        selectionView = view
        self.contentView = view
    }
    
    func show() {
        self.makeKeyAndOrderFront(nil)
        if let view = selectionView {
            self.makeFirstResponder(view)
        }
        NSCursor.crosshair.push()
    }
    
    private func handleSelectionComplete(_ rect: CGRect) {
        NSCursor.pop()
        self.orderOut(nil)
        completion?(rect)
        completion = nil
    }
    
    private func handleCancel() {
        NSCursor.pop()
        self.orderOut(nil)
        completion?(nil)
        completion = nil
    }
}

class AreaSelectionView: NSView {
    var onSelectionComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    
    private var selectionStart: NSPoint?
    private var selectionEnd: NSPoint?
    private var isSelecting = false
    
    private var dimensionLabel: NSTextField?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func draw(_ dirtyRect: NSRect) {
        // Semi-transparent overlay
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()
        
        // Draw selection rectangle if selecting
        if let start = selectionStart, let end = selectionEnd {
            let selectionRect = rectFromPoints(start, end)
            
            // Clear the selection area (make it transparent)
            NSColor.clear.setFill()
            selectionRect.fill()
            
            // Draw border
            NSColor.white.setStroke()
            let path = NSBezierPath(rect: selectionRect)
            path.lineWidth = 2
            path.stroke()
            
            // Draw dashed inner border
            NSColor.white.withAlphaComponent(0.5).setStroke()
            let dashPath = NSBezierPath(rect: selectionRect.insetBy(dx: 1, dy: 1))
            dashPath.lineWidth = 1
            dashPath.setLineDash([4, 4], count: 2, phase: 0)
            dashPath.stroke()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        selectionStart = point
        selectionEnd = point
        isSelecting = true
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isSelecting else { return }
        let point = convert(event.locationInWindow, from: nil)
        selectionEnd = point
        needsDisplay = true
        updateDimensionLabel()
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isSelecting, let start = selectionStart, let end = selectionEnd else {
            return
        }
        
        isSelecting = false
        let rect = rectFromPoints(start, end)
        
        // Minimum size check
        if rect.width > 10 && rect.height > 10 {
            // Convert to screen coordinates (flip Y)
            guard let screen = NSScreen.main else {
                onCancel?()
                return
            }
            
            let flippedRect = CGRect(
                x: rect.origin.x,
                y: screen.frame.height - rect.origin.y - rect.height,
                width: rect.width,
                height: rect.height
            )
            
            onSelectionComplete?(flippedRect)
        } else {
            onCancel?()
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        }
    }
    
    private func rectFromPoints(_ p1: NSPoint, _ p2: NSPoint) -> NSRect {
        let x = min(p1.x, p2.x)
        let y = min(p1.y, p2.y)
        let width = abs(p2.x - p1.x)
        let height = abs(p2.y - p1.y)
        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    private func updateDimensionLabel() {
        guard let start = selectionStart, let end = selectionEnd else { return }
        
        let rect = rectFromPoints(start, end)
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        
        if dimensionLabel == nil {
            let label = NSTextField(labelWithString: text)
            label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
            label.textColor = .white
            label.backgroundColor = NSColor.black.withAlphaComponent(0.7)
            label.isBordered = false
            label.drawsBackground = true
            label.alignment = .center
            label.wantsLayer = true
            label.layer?.cornerRadius = 4
            addSubview(label)
            dimensionLabel = label
        }
        
        dimensionLabel?.stringValue = text
        dimensionLabel?.sizeToFit()
        
        // Position below selection
        if let label = dimensionLabel {
            var labelFrame = label.frame
            labelFrame.size.width += 12
            labelFrame.origin.x = rect.midX - labelFrame.width / 2
            labelFrame.origin.y = rect.minY - labelFrame.height - 8
            label.frame = labelFrame
        }
    }
}
