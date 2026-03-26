import AppKit
import ScreenCaptureKit

// MARK: - Coordinate Conversion Utilities

extension NSScreen {
    /// The main display's height - used as the flip reference for SCK coordinate conversion.
    /// SCK coordinates are anchored to the main display's top-left corner, not the full virtual display.
    private static var mainDisplayHeight: CGFloat {
        // Main screen is always first in the screens array and has origin at (0, 0)
        screens.first?.frame.height ?? 0
    }

    /// Convert Cocoa point (bottom-left origin) to ScreenCaptureKit point (top-left origin)
    /// SCK uses main display's top-left as origin; Y increases downward.
    static func convertToSCK(_ cocoaPoint: NSPoint) -> CGPoint {
        return CGPoint(x: cocoaPoint.x, y: mainDisplayHeight - cocoaPoint.y)
    }

    /// Convert ScreenCaptureKit point (top-left origin) to Cocoa point (bottom-left origin)
    static func convertFromSCK(_ sckPoint: CGPoint) -> NSPoint {
        return NSPoint(x: sckPoint.x, y: mainDisplayHeight - sckPoint.y)
    }

    /// Convert ScreenCaptureKit frame (top-left origin) to Cocoa frame (bottom-left origin)
    static func convertFrameFromSCK(_ sckFrame: CGRect) -> NSRect {
        // SCK frame's origin is at top-left; Cocoa frame's origin is at bottom-left
        // The bottom of the SCK frame in Cocoa coords is: mainHeight - (sckY + sckHeight)
        return NSRect(
            x: sckFrame.origin.x,
            y: mainDisplayHeight - sckFrame.origin.y - sckFrame.height,
            width: sckFrame.width,
            height: sckFrame.height
        )
    }
}

/// Result of area/window selection - either an area rect or a window
enum AreaSelectorResult {
    case area(CGRect)
    case window(SCWindow)
    case cancelled
}

/// Selection mode for the area selector
enum SelectionMode {
    case area
    case window
}

/// Manages multiple overlay windows for area selection across all displays
/// Supports Space key to toggle to window selection mode (like native macOS)
class AreaSelectorWindow {
    private var overlayWindows: [AreaOverlayWindow] = []
    private var completion: ((AreaSelectorResult) -> Void)?
    private var coordinator: AreaSelectionCoordinator?
    private var hasCompleted = false
    private var localKeyMonitor: Any?
    
    init(screenCaptures: [(screen: NSScreen, image: CGImage)], completion: @escaping (AreaSelectorResult) -> Void) {
        self.completion = completion

        // Create coordinator to sync selection state across screens
        coordinator = AreaSelectionCoordinator()
        coordinator?.onAreaComplete = { [weak self] rect in
            self?.handleAreaComplete(rect)
        }
        coordinator?.onWindowSelected = { [weak self] window in
            self?.handleWindowSelected(window)
        }
        coordinator?.onCancel = { [weak self] in
            self?.handleCancel()
        }

        // Pre-fetch available windows for window mode
        Task {
            await coordinator?.loadWindows()
        }

        // Create an overlay window for each screen, matching frozen captures by frame origin
        for screen in NSScreen.screens {
            // Find the frozen capture for this screen by matching frame origin
            let frozenImage = screenCaptures.first(where: { $0.screen.frame.origin == screen.frame.origin })?.image
            let window = AreaOverlayWindow(screen: screen, coordinator: coordinator!, frozenImage: frozenImage)
            overlayWindows.append(window)
        }
    }
    
    func show() {
        NSCursor.crosshair.push()
        installLocalKeyMonitor()
        for window in overlayWindows {
            window.show()
        }
    }

    func toggleMode() {
        coordinator?.toggleMode()
    }

    func cancel() {
        coordinator?.cancel()
    }

    private func handleAreaComplete(_ rect: CGRect) {
        guard !hasCompleted else { return }
        complete(with: .area(rect))
    }

    private func handleWindowSelected(_ window: SCWindow) {
        guard !hasCompleted else { return }
        complete(with: .window(window))
    }

    private func handleCancel() {
        guard !hasCompleted else { return }
        complete(with: .cancelled)
    }

    private func complete(with result: AreaSelectorResult) {
        hasCompleted = true
        removeLocalKeyMonitor()
        NSCursor.pop()
        for window in overlayWindows {
            window.orderOut(nil)
        }
        completion?(result)
        completion = nil
    }

    private func installLocalKeyMonitor() {
        guard localKeyMonitor == nil else { return }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.hasCompleted else {
                return event
            }

            switch event.keyCode {
            case 49: // Space
                self.toggleMode()
                return nil
            case 53: // Escape
                self.cancel()
                return nil
            default:
                return event
            }
        }
    }

    private func removeLocalKeyMonitor() {
        guard let localKeyMonitor else { return }
        NSEvent.removeMonitor(localKeyMonitor)
        self.localKeyMonitor = nil
    }
}

/// Coordinates selection state across multiple screens
class AreaSelectionCoordinator {
    var onAreaComplete: ((CGRect) -> Void)?
    var onWindowSelected: ((SCWindow) -> Void)?
    var onCancel: (() -> Void)?
    
    // Current mode
    var mode: SelectionMode = .area {
        didSet {
            if mode != oldValue {
                updateCursor()
                updateAllViews()
            }
        }
    }
    
    // Area selection state
    var isSelecting = false
    var selectionStart: NSPoint?
    var selectionEnd: NSPoint?
    var activeScreen: NSScreen?
    
    // Window selection state
    var availableWindows: [SCWindow] = []
    var highlightedWindow: SCWindow?
    private var windowLoadGeneration: Int = 0
    
    // All registered views for cross-screen updates
    var views: [AreaSelectionView] = []
    
    func loadWindows() async {
        let generation = await MainActor.run {
            windowLoadGeneration += 1
            return windowLoadGeneration
        }
        do {
            // excludingDesktopWindows: true filters out Finder desktop windows
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let ownBundleID = Bundle.main.bundleIdentifier

            let filteredWindows = content.windows.filter { window in
                    // Must have owningApplication (filters out system artifacts)
                    guard let app = window.owningApplication else {
                        return false
                    }

                    // Exclude our own app's windows (overlays, preferences, etc.)
                    if let ownID = ownBundleID, app.bundleIdentifier == ownID {
                        return false
                    }

                    // Exclude Dock and Notification Center (system UI with misleading frames)
                    let excludedBundles = ["com.apple.dock", "com.apple.notificationcenterui"]
                    if excludedBundles.contains(app.bundleIdentifier) {
                        return false
                    }

                    // Must have a reasonable size
                    guard window.frame.width > 50 && window.frame.height > 50 else {
                        return false
                    }

                    // Must have a title or be from a non-system app
                    let hasTitle = window.title?.isEmpty == false
                    let isSystemUI = app.bundleIdentifier.hasPrefix("com.apple.") && window.title == nil

                    return hasTitle || !isSystemUI
                }
            let orderedWindows = WindowOrdering.sortByZOrder(filteredWindows)

            await MainActor.run {
                guard self.windowLoadGeneration == generation else {
                    return
                }
                self.availableWindows = orderedWindows
                self.highlightedWindow = nil
                self.updateAllViews()
            }
        } catch {
            // Windows will be empty, but area selection will still work
        }
    }
    
    private func updateCursor() {
        NSCursor.pop()
        switch mode {
        case .area:
            NSCursor.crosshair.push()
        case .window:
            NSCursor.pointingHand.push()
        }
    }
    
    func toggleMode() {
        let newMode: SelectionMode = (mode == .area) ? .window : .area
        mode = newMode

        // Refresh window list when entering window mode to get current z-order
        if newMode == .window {
            Task {
                await loadWindows()
            }
        }
    }
    
    func startSelection(at point: NSPoint, screen: NSScreen) {
        guard mode == .area else { return }
        isSelecting = true
        selectionStart = point
        selectionEnd = point
        activeScreen = screen
        updateAllViews()
    }
    
    func updateSelection(to point: NSPoint) {
        guard mode == .area, isSelecting else { return }
        selectionEnd = point
        updateAllViews()
    }
    
    func endSelection(at point: NSPoint) {
        guard mode == .area, isSelecting, let start = selectionStart else { return }
        isSelecting = false
        selectionEnd = point
        
        let rect = rectFromPoints(start, point)
        
        // Minimum size check
        if rect.width > 10 && rect.height > 10 {
            onAreaComplete?(rect)
        } else {
            onCancel?()
        }
    }
    
    func handleMouseMoved(at globalPoint: NSPoint) {
        guard mode == .window else { return }
        highlightedWindow = findWindowAt(globalPoint)
        updateAllViews()
    }
    
    func handleClick(at globalPoint: NSPoint) {
        if mode == .window, let window = highlightedWindow {
            onWindowSelected?(window)
        }
    }
    
    private func findWindowAt(_ point: NSPoint) -> SCWindow? {
        // Convert Cocoa coordinates to SCK coordinates using full virtual display bounds
        let sckPoint = NSScreen.convertToSCK(point)

        // Find windows that contain this point
        // Windows are sorted front-to-back by WindowOrdering, so first match is frontmost
        for window in availableWindows {
            if window.frame.contains(sckPoint) {
                return window
            }
        }
        return nil
    }
    
    func cancel() {
        isSelecting = false
        selectionStart = nil
        selectionEnd = nil
        activeScreen = nil
        highlightedWindow = nil
        onCancel?()
    }
    
    private func rectFromPoints(_ p1: NSPoint, _ p2: NSPoint) -> NSRect {
        let x = min(p1.x, p2.x)
        let y = min(p1.y, p2.y)
        let width = abs(p2.x - p1.x)
        let height = abs(p2.y - p1.y)
        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    func updateAllViews() {
        for view in views {
            view.needsDisplay = true
            view.updateDimensionLabel()
        }
    }
}

/// Individual overlay window for one screen
class AreaOverlayWindow: NSPanel {
    private var selectionView: AreaSelectionView?
    private weak var coordinator: AreaSelectionCoordinator?
    let associatedScreen: NSScreen

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen, coordinator: AreaSelectionCoordinator, frozenImage: CGImage?) {
        self.coordinator = coordinator
        self.associatedScreen = screen

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Configure panel
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hasShadow = false
        self.hidesOnDeactivate = false
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = true

        // Create selection view - use local bounds (0,0 origin), not screen coordinates
        let viewFrame = NSRect(origin: .zero, size: screen.frame.size)
        let view = AreaSelectionView(frame: viewFrame, screen: screen, coordinator: coordinator, frozenImage: frozenImage)
        coordinator.views.append(view)
        selectionView = view
        self.contentView = view
    }

    func show() {
        self.alphaValue = 0
        self.orderFrontRegardless()
        self.selectionView?.display()  // Force synchronous draw before showing
        self.alphaValue = 1
    }

    /// Ignore cancelOperation — Escape is handled by the CGEvent tap and local key monitor.
    /// The default cancelOperation fires during app deactivation (e.g. menu bar clicks),
    /// which would incorrectly dismiss the overlay.
    override func cancelOperation(_ sender: Any?) {
        // Intentionally empty
    }
}

class AreaSelectionView: NSView {
    private weak var coordinator: AreaSelectionCoordinator?
    private let screen: NSScreen
    private let frozenImage: NSImage?

    private var dimensionLabel: NSTextField?
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    // Accept mouse events without requiring window activation first
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame: NSRect, screen: NSScreen, coordinator: AreaSelectionCoordinator, frozenImage: CGImage?) {
        self.screen = screen
        self.coordinator = coordinator
        // Convert CGImage to NSImage sized to the screen's point dimensions
        if let cgImage = frozenImage {
            let nsImage = NSImage(cgImage: cgImage, size: frame.size)
            self.frozenImage = nsImage
        } else {
            self.frozenImage = nil
        }
        super.init(frame: frame)

        // Set up tracking area for mouse moved events
        updateTrackingArea()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func updateTrackingArea() {
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        if let area = trackingArea {
            addTrackingArea(area)
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        guard let coordinator = coordinator else {
            // Fallback: draw frozen image dimmed, or just dim overlay
            drawFrozenImageDimmed()
            return
        }
        
        switch coordinator.mode {
        case .area:
            drawAreaMode()
        case .window:
            drawWindowMode()
        }
        
        // Draw mode indicator
        drawModeIndicator()
    }
    
    /// Draw frozen image with dim overlay on top. Falls back to solid dim if no frozen image.
    private func drawFrozenImageDimmed() {
        if let frozenImage = frozenImage {
            frozenImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
        }
        NSColor.black.withAlphaComponent(0.3).setFill()
        bounds.fill()
    }

    private func drawAreaMode() {
        // Draw selection rectangle if selecting
        if let coordinator = coordinator,
           let start = coordinator.selectionStart,
           let end = coordinator.selectionEnd {

            // Convert global screen coordinates to local view coordinates
            let localStart = NSPoint(x: start.x - screen.frame.origin.x, y: start.y - screen.frame.origin.y)
            let localEnd = NSPoint(x: end.x - screen.frame.origin.x, y: end.y - screen.frame.origin.y)

            let selectionRect = rectFromPoints(localStart, localEnd)

            // Draw frozen image dimmed everywhere
            drawFrozenImageDimmed()

            // Draw frozen image at full brightness inside the selection rect (bright cutout)
            if selectionRect.intersects(bounds), let frozenImage = frozenImage {
                let clippedRect = selectionRect.intersection(bounds)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: clippedRect).setClip()
                frozenImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
                NSGraphicsContext.restoreGraphicsState()
            }

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
            // No selection yet - draw frozen image dimmed
            drawFrozenImageDimmed()
        }
    }
    
    private func drawWindowMode() {
        // Draw frozen image dimmed
        drawFrozenImageDimmed()

        // Highlight the hovered window
        if let coordinator = coordinator, let window = coordinator.highlightedWindow {
            drawWindowHighlight(window)
        }
    }

    private func drawWindowHighlight(_ window: SCWindow) {
        // Convert window frame to screen coordinates, then to view coordinates
        let windowFrame = window.frame
        let localFrame = convertWindowFrameToView(windowFrame)

        // Only draw if window is on this screen
        guard localFrame.intersects(bounds) else { return }

        // Draw frozen image at full brightness in the window area (cut out the dim)
        let clippedFrame = localFrame.intersection(bounds)
        if let frozenImage = frozenImage {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: clippedFrame).setClip()
            frozenImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
            NSGraphicsContext.restoreGraphicsState()
        } else {
            // Fallback: clear the window area
            NSColor.clear.setFill()
            clippedFrame.fill()
        }

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
    
    private func drawModeIndicator() {
        guard let coordinator = coordinator else { return }
        
        let modeText: String
        let hintText: String
        
        switch coordinator.mode {
        case .area:
            modeText = "Area Capture"
            hintText = "Drag to select • Press Space for window mode • Esc to cancel"
        case .window:
            modeText = "Window Capture"
            hintText = "Click a window to capture • Press Space for area mode • Esc to cancel"
        }
        
        // Draw mode pill at top center
        let modeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let modeString = NSAttributedString(string: modeText, attributes: modeAttrs)
        let modeSize = modeString.size()
        
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.8)
        ]
        let hintString = NSAttributedString(string: hintText, attributes: hintAttrs)
        let hintSize = hintString.size()
        
        let totalWidth = max(modeSize.width, hintSize.width)
        let padding: CGFloat = 16
        let spacing: CGFloat = 4
        let totalHeight = modeSize.height + hintSize.height + spacing
        
        let pillRect = NSRect(
            x: (bounds.width - totalWidth) / 2 - padding,
            y: bounds.height - 80 - totalHeight / 2,
            width: totalWidth + padding * 2,
            height: totalHeight + padding
        )
        
        NSColor.black.withAlphaComponent(0.7).setFill()
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 8, yRadius: 8)
        pillPath.fill()
        
        // Draw mode text
        let modePoint = NSPoint(
            x: (bounds.width - modeSize.width) / 2,
            y: pillRect.origin.y + padding / 2 + hintSize.height + spacing
        )
        modeString.draw(at: modePoint)
        
        // Draw hint text
        let hintPoint = NSPoint(
            x: (bounds.width - hintSize.width) / 2,
            y: pillRect.origin.y + padding / 2
        )
        hintString.draw(at: hintPoint)
    }
    
    override func mouseDown(with event: NSEvent) {
        guard let coordinator = coordinator else { return }
        
        let localPoint = convert(event.locationInWindow, from: nil)
        let globalPoint = NSPoint(x: localPoint.x + screen.frame.origin.x, y: localPoint.y + screen.frame.origin.y)
        
        switch coordinator.mode {
        case .area:
            coordinator.startSelection(at: globalPoint, screen: screen)
        case .window:
            coordinator.handleClick(at: globalPoint)
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let coordinator = coordinator, coordinator.mode == .area else { return }
        
        let localPoint = convert(event.locationInWindow, from: nil)
        let globalPoint = NSPoint(x: localPoint.x + screen.frame.origin.x, y: localPoint.y + screen.frame.origin.y)
        coordinator.updateSelection(to: globalPoint)
    }
    
    override func mouseUp(with event: NSEvent) {
        guard let coordinator = coordinator, coordinator.mode == .area else { return }
        
        let localPoint = convert(event.locationInWindow, from: nil)
        let globalPoint = NSPoint(x: localPoint.x + screen.frame.origin.x, y: localPoint.y + screen.frame.origin.y)
        
        coordinator.endSelection(at: globalPoint)
    }
    
    override func mouseMoved(with event: NSEvent) {
        guard let coordinator = coordinator else { return }
        
        let localPoint = convert(event.locationInWindow, from: nil)
        let globalPoint = NSPoint(x: localPoint.x + screen.frame.origin.x, y: localPoint.y + screen.frame.origin.y)
        coordinator.handleMouseMoved(at: globalPoint)
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
              coordinator.mode == .area,
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
