import AppKit

/// Manages multiple overlay windows for area selection across all displays
class AreaSelectorWindow {
    private var overlayWindows: [AreaOverlayWindow] = []
    private var completion: ((CGRect?, NSScreen?) -> Void)?
    private var coordinator: AreaSelectionCoordinator?
    
    init(completion: @escaping (CGRect?, NSScreen?) -> Void) {
        self.completion = completion
        
        // Create coordinator to sync selection state across screens
        coordinator = AreaSelectionCoordinator()
        coordinator?.onSelectionComplete = { [weak self] rect, screen in
            self?.handleSelectionComplete(rect, screen: screen)
        }
        coordinator?.onCancel = { [weak self] in
            self?.handleCancel()
        }
        
        // Create an overlay window for each screen
        for screen in NSScreen.screens {
            let window = AreaOverlayWindow(screen: screen, coordinator: coordinator!)
            overlayWindows.append(window)
        }
    }
    
    func show() {
        NSCursor.crosshair.push()
        for window in overlayWindows {
            window.show()
        }
    }
    
    private func handleSelectionComplete(_ rect: CGRect, screen: NSScreen) {
        NSCursor.pop()
        for window in overlayWindows {
            window.orderOut(nil)
        }
        completion?(rect, screen)
        completion = nil
    }
    
    private func handleCancel() {
        NSCursor.pop()
        for window in overlayWindows {
            window.orderOut(nil)
        }
        completion?(nil, nil)
        completion = nil
    }
}

/// Coordinates selection state across multiple screens
class AreaSelectionCoordinator {
    var onSelectionComplete: ((CGRect, NSScreen) -> Void)?
    var onCancel: (() -> Void)?
    
    var isSelecting = false
    var selectionStart: NSPoint?
    var selectionEnd: NSPoint?
    var activeScreen: NSScreen?
    
    // All registered views for cross-screen updates
    var views: [AreaSelectionView] = []
    
    func startSelection(at point: NSPoint, screen: NSScreen) {
        isSelecting = true
        selectionStart = point
        selectionEnd = point
        activeScreen = screen
        updateAllViews()
    }
    
    func updateSelection(to point: NSPoint) {
        guard isSelecting else { return }
        selectionEnd = point
        updateAllViews()
    }
    
    func endSelection(at point: NSPoint, screen: NSScreen) {
        guard isSelecting, let start = selectionStart else { return }
        isSelecting = false
        selectionEnd = point
        
        let rect = rectFromPoints(start, point)
        
        // Minimum size check
        if rect.width > 10 && rect.height > 10 {
            // Convert to screen coordinates (flip Y for the active screen)
            let flippedRect = CGRect(
                x: rect.origin.x - screen.frame.origin.x,
                y: screen.frame.height - (rect.origin.y - screen.frame.origin.y) - rect.height,
                width: rect.width,
                height: rect.height
            )
            onSelectionComplete?(flippedRect, screen)
        } else {
            onCancel?()
        }
    }
    
    func cancel() {
        isSelecting = false
        selectionStart = nil
        selectionEnd = nil
        activeScreen = nil
        onCancel?()
    }
    
    private func rectFromPoints(_ p1: NSPoint, _ p2: NSPoint) -> NSRect {
        let x = min(p1.x, p2.x)
        let y = min(p1.y, p2.y)
        let width = abs(p2.x - p1.x)
        let height = abs(p2.y - p1.y)
        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    private func updateAllViews() {
        for view in views {
            view.needsDisplay = true
            view.updateDimensionLabel()
        }
    }
}

/// Individual overlay window for one screen
class AreaOverlayWindow: NSWindow {
    private var selectionView: AreaSelectionView?
    private weak var coordinator: AreaSelectionCoordinator?
    let associatedScreen: NSScreen
    
    init(screen: NSScreen, coordinator: AreaSelectionCoordinator) {
        self.coordinator = coordinator
        self.associatedScreen = screen
        
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
        let view = AreaSelectionView(frame: screen.frame, screen: screen, coordinator: coordinator)
        coordinator.views.append(view)
        selectionView = view
        self.contentView = view
    }
    
    func show() {
        self.makeKeyAndOrderFront(nil)
        if let view = selectionView {
            self.makeFirstResponder(view)
        }
    }
}

class AreaSelectionView: NSView {
    private weak var coordinator: AreaSelectionCoordinator?
    private let screen: NSScreen
    
    private var dimensionLabel: NSTextField?
    
    override var acceptsFirstResponder: Bool { true }
    
    init(frame: NSRect, screen: NSScreen, coordinator: AreaSelectionCoordinator) {
        self.screen = screen
        self.coordinator = coordinator
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        // Draw selection rectangle if selecting
        if let coordinator = coordinator,
           let start = coordinator.selectionStart,
           let end = coordinator.selectionEnd {
            
            // Convert global screen coordinates to local view coordinates
            let localStart = NSPoint(x: start.x - screen.frame.origin.x, y: start.y - screen.frame.origin.y)
            let localEnd = NSPoint(x: end.x - screen.frame.origin.x, y: end.y - screen.frame.origin.y)
            
            let selectionRect = rectFromPoints(localStart, localEnd)

            // Create a path that covers the entire view but excludes the selection
            let overlayPath = NSBezierPath(rect: bounds)
            if selectionRect.intersects(bounds) {
                let clippedRect = selectionRect.intersection(bounds)
                overlayPath.append(NSBezierPath(rect: clippedRect).reversed)
            }
            overlayPath.windingRule = .evenOdd

            // Fill the overlay (everything except selection)
            NSColor.black.withAlphaComponent(0.3).setFill()
            overlayPath.fill()

            // Draw border around selection (only on the screen where selection is visible)
            if selectionRect.intersects(bounds) && bounds.contains(selectionRect) {
                NSColor.white.setStroke()
                let borderPath = NSBezierPath(rect: selectionRect)
                borderPath.lineWidth = 2
                borderPath.stroke()

                // Draw dashed inner border
                NSColor.white.withAlphaComponent(0.5).setStroke()
                let dashPath = NSBezierPath(rect: selectionRect.insetBy(dx: 1, dy: 1))
                dashPath.lineWidth = 1
                dashPath.setLineDash([4, 4], count: 2, phase: 0)
                dashPath.stroke()
            }
        } else {
            // No selection yet - fill entire view with dim overlay
            NSColor.black.withAlphaComponent(0.3).setFill()
            bounds.fill()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        // Convert to global screen coordinates
        let localPoint = convert(event.locationInWindow, from: nil)
        let globalPoint = NSPoint(x: localPoint.x + screen.frame.origin.x, y: localPoint.y + screen.frame.origin.y)
        coordinator?.startSelection(at: globalPoint, screen: screen)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let globalPoint = NSPoint(x: localPoint.x + screen.frame.origin.x, y: localPoint.y + screen.frame.origin.y)
        coordinator?.updateSelection(to: globalPoint)
    }
    
    override func mouseUp(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let globalPoint = NSPoint(x: localPoint.x + screen.frame.origin.x, y: localPoint.y + screen.frame.origin.y)
        
        // Determine which screen the selection ends on
        let endScreen = NSScreen.screens.first { $0.frame.contains(globalPoint) } ?? screen
        coordinator?.endSelection(at: globalPoint, screen: endScreen)
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            coordinator?.cancel()
        }
    }
    
    private func rectFromPoints(_ p1: NSPoint, _ p2: NSPoint) -> NSRect {
        let x = min(p1.x, p2.x)
        let y = min(p1.y, p2.y)
        let width = abs(p2.x - p1.x)
        let height = abs(p2.y - p1.y)
        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    func updateDimensionLabel() {
        guard let coordinator = coordinator,
              let start = coordinator.selectionStart,
              let end = coordinator.selectionEnd,
              coordinator.activeScreen == screen else {
            dimensionLabel?.isHidden = true
            return
        }
        
        // Convert to local coordinates
        let localStart = NSPoint(x: start.x - screen.frame.origin.x, y: start.y - screen.frame.origin.y)
        let localEnd = NSPoint(x: end.x - screen.frame.origin.x, y: end.y - screen.frame.origin.y)
        
        let rect = rectFromPoints(localStart, localEnd)
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
        
        dimensionLabel?.isHidden = false
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
