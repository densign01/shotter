import AppKit
import ScreenCaptureKit
import os.log

private let logger = Logger(subsystem: "com.densign.shotter", category: "WindowSelector")

/// Controller that manages window selection UI across all screens
class WindowSelectorController {
    private var overlayWindows: [WindowSelectorOverlay] = []
    private var completion: ((SCWindow?) -> Void)?
    private var windows: [SCWindow]
    private var highlightedWindow: SCWindow?
    
    init(windows: [SCWindow], completion: @escaping (SCWindow?) -> Void) {
        self.windows = windows
        self.completion = completion
        
        // Create an overlay for each screen
        for screen in NSScreen.screens {
            let overlay = WindowSelectorOverlay(
                screen: screen,
                windows: windows,
                onWindowHovered: { [weak self] window in
                    self?.highlightWindow(window)
                },
                onWindowSelected: { [weak self] window in
                    self?.selectWindow(window)
                },
                onCancel: { [weak self] in
                    self?.cancel()
                }
            )
            overlayWindows.append(overlay)
        }
    }
    
    func show() {
        NSCursor.pointingHand.push()
        for window in overlayWindows {
            window.show()
        }
    }
    
    private func highlightWindow(_ window: SCWindow?) {
        highlightedWindow = window
        for overlay in overlayWindows {
            overlay.updateHighlight(window)
        }
    }
    
    private func selectWindow(_ window: SCWindow) {
        NSCursor.pop()
        for overlay in overlayWindows {
            overlay.orderOut(nil)
        }
        completion?(window)
        completion = nil
    }
    
    private func cancel() {
        NSCursor.pop()
        for overlay in overlayWindows {
            overlay.orderOut(nil)
        }
        completion?(nil)
        completion = nil
    }
}

/// Overlay window for one screen during window selection
class WindowSelectorOverlay: NSPanel {
    private var selectorView: WindowSelectorView?
    let associatedScreen: NSScreen

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    init(
        screen: NSScreen,
        windows: [SCWindow],
        onWindowHovered: @escaping (SCWindow?) -> Void,
        onWindowSelected: @escaping (SCWindow) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.associatedScreen = screen

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Configure panel for keyboard event delivery
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.becomesKeyOnlyIfNeeded = false
        
        // Create selector view
        let view = WindowSelectorView(
            frame: screen.frame,
            screen: screen,
            windows: windows,
            onWindowHovered: onWindowHovered,
            onWindowSelected: onWindowSelected,
            onCancel: onCancel
        )
        selectorView = view
        self.contentView = view
    }
    
    func show() {
        self.makeKeyAndOrderFront(nil)
        if let view = selectorView {
            self.makeFirstResponder(view)
        }
    }

    /// Handle Escape key to cancel selection (prevents default app behavior)
    override func cancelOperation(_ sender: Any?) {
        selectorView?.cancelSelection()
    }

    func updateHighlight(_ window: SCWindow?) {
        selectorView?.highlightedWindow = window
        selectorView?.needsDisplay = true
    }
}

/// View that draws window highlights and handles mouse interaction
class WindowSelectorView: NSView {
    private let screen: NSScreen
    private let windows: [SCWindow]
    private let onWindowHovered: (SCWindow?) -> Void
    private let onWindowSelected: (SCWindow) -> Void
    private let onCancel: () -> Void
    
    var highlightedWindow: SCWindow?

    override var acceptsFirstResponder: Bool { true }

    func cancelSelection() {
        onCancel()
    }
    
    init(
        frame: NSRect,
        screen: NSScreen,
        windows: [SCWindow],
        onWindowHovered: @escaping (SCWindow?) -> Void,
        onWindowSelected: @escaping (SCWindow) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.screen = screen
        self.windows = windows
        self.onWindowHovered = onWindowHovered
        self.onWindowSelected = onWindowSelected
        self.onCancel = onCancel
        super.init(frame: frame)
        
        // Enable tracking for mouse moved events
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        // Semi-transparent overlay
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()
        
        // Draw instructions
        drawInstructions()
        
        // Highlight the hovered window
        if let window = highlightedWindow {
            drawWindowHighlight(window)
        }
    }
    
    private func drawInstructions() {
        let text = "Click a window to capture it • Press Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        
        // Draw background pill
        let padding: CGFloat = 16
        let pillRect = NSRect(
            x: (bounds.width - textSize.width) / 2 - padding,
            y: bounds.height - 80 - textSize.height / 2,
            width: textSize.width + padding * 2,
            height: textSize.height + padding
        )
        
        NSColor.black.withAlphaComponent(0.7).setFill()
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillRect.height / 2, yRadius: pillRect.height / 2)
        pillPath.fill()
        
        // Draw text
        let textPoint = NSPoint(
            x: (bounds.width - textSize.width) / 2,
            y: bounds.height - 80 - textSize.height / 2 + padding / 2
        )
        attributedString.draw(at: textPoint)
    }
    
    private func drawWindowHighlight(_ window: SCWindow) {
        // Convert window frame to screen coordinates, then to view coordinates
        let windowFrame = window.frame
        
        // Window frame is in global screen coordinates (origin at bottom-left of main display)
        // Convert to this screen's coordinate space
        let localFrame = convertWindowFrameToView(windowFrame)
        
        // Only draw if window is on this screen
        guard localFrame.intersects(bounds) else { return }
        
        // Clear the window area
        NSColor.clear.setFill()
        localFrame.intersection(bounds).fill()
        
        // Draw highlight border
        NSColor.systemBlue.setStroke()
        let borderPath = NSBezierPath(rect: localFrame)
        borderPath.lineWidth = 4
        borderPath.stroke()
        
        // Draw window info label
        drawWindowLabel(window, at: localFrame)
    }
    
    private func convertWindowFrameToView(_ windowFrame: CGRect) -> NSRect {
        // Convert from SCK coordinates (top-left origin) to Cocoa coordinates (bottom-left origin)
        let cocoaFrame = NSScreen.convertFrameFromSCK(windowFrame)

        // Convert to this view's local coordinate space
        return NSRect(
            x: cocoaFrame.origin.x - screen.frame.origin.x,
            y: cocoaFrame.origin.y - screen.frame.origin.y,
            width: cocoaFrame.width,
            height: cocoaFrame.height
        )
    }
    
    private func drawWindowLabel(_ window: SCWindow, at frame: NSRect) {
        let appName = window.owningApplication?.applicationName ?? "Unknown"
        let windowTitle = window.title ?? ""
        let labelText = windowTitle.isEmpty ? appName : "\(appName): \(windowTitle)"
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let attributedString = NSAttributedString(string: labelText, attributes: attributes)
        let textSize = attributedString.size()
        
        // Position above the window
        let padding: CGFloat = 8
        let labelRect = NSRect(
            x: frame.midX - textSize.width / 2 - padding,
            y: frame.maxY + 8,
            width: textSize.width + padding * 2,
            height: textSize.height + padding
        )
        
        // Draw background
        NSColor.systemBlue.setFill()
        let labelPath = NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4)
        labelPath.fill()
        
        // Draw text
        attributedString.draw(at: NSPoint(x: labelRect.origin.x + padding, y: labelRect.origin.y + padding / 2))
    }
    
    override func mouseMoved(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let globalPoint = NSPoint(x: localPoint.x + screen.frame.origin.x, y: localPoint.y + screen.frame.origin.y)
        
        // Find window under cursor
        let hoveredWindow = findWindowAt(globalPoint)
        onWindowHovered(hoveredWindow)
    }
    
    override func mouseDown(with event: NSEvent) {
        if let window = highlightedWindow {
            onWindowSelected(window)
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel()
        }
    }
    
    private func findWindowAt(_ point: NSPoint) -> SCWindow? {
        // Convert Cocoa coordinates to SCK coordinates using full virtual display bounds
        let sckPoint = NSScreen.convertToSCK(point)

        // Find windows that contain this point
        // SCShareableContent.windows is already sorted front-to-back, so first match is frontmost
        for window in windows {
            if window.frame.contains(sckPoint) {
                return window
            }
        }
        return nil
    }
}
