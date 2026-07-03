import AppKit
import ScreenCaptureKit
import os.log

private let logger = Logger(subsystem: "com.densign.shotter", category: "Capture")

/// Represents a display for capture
struct CaptureDisplay: Identifiable {
    let id: CGDirectDisplayID
    let scDisplay: SCDisplay
    let screen: NSScreen?
    let name: String
    let isMain: Bool
    let frame: CGRect

    var scaleFactor: CGFloat {
        screen?.backingScaleFactor ?? 2.0
    }
}

/// Result of area selection in global Cocoa coordinates.
struct AreaCaptureResult {
    let globalRect: CGRect
}

/// Finalized capture output with optional placement metadata.
struct CaptureResult {
    let image: NSImage
    let preferredScreen: NSScreen?
}

class CaptureEngine {
    private var availableContent: SCShareableContent?
    private weak var hotkeyManager: HotkeyManager?

    // Retain selectors to prevent deallocation while showing
    private var activeAreaSelector: AreaSelectorWindow?
    private var activeWindowSelector: WindowSelectorController?

    // Guards against re-entrant captures (e.g. pressing the hotkey twice),
    // which would orphan the active selector and permanently hang its task.
    // Only read/written on the main actor.
    private var isCaptureFlowActive = false

    /// Atomically claim the capture flow. Returns false if a capture is already in progress.
    @MainActor
    private func beginCaptureFlow() -> Bool {
        guard !isCaptureFlowActive else { return false }
        isCaptureFlowActive = true
        return true
    }

    private func endCaptureFlow() {
        Task { @MainActor in
            self.isCaptureFlowActive = false
        }
    }

    // Pre-capture cache for preserving menus/tooltips during hotkey capture
    private var preCapturedScreens: [(screen: NSScreen, image: CGImage)]?
    private var preCaptureTimestamp: Date?
    private var isPreCapturing = false
    private static let preCaptureTimeout: TimeInterval = 0.5

    init(hotkeyManager: HotkeyManager? = nil) {
        self.hotkeyManager = hotkeyManager

        Task {
            await refreshAvailableContent()
        }
    }

    private func refreshAvailableContent() async {
        do {
            // excludingDesktopWindows: true filters out Finder desktop windows
            availableContent = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            logger.error("Failed to get available content: \(error.localizedDescription)")
        }
    }

    // MARK: - Display Enumeration

    /// Get all available displays for capture
    func getAvailableDisplays() async -> [CaptureDisplay] {
        await refreshAvailableContent()

        guard let displays = availableContent?.displays else {
            return []
        }

        let screens = NSScreen.screens

        return displays.compactMap { scDisplay -> CaptureDisplay? in
            let matchingScreen = screens.first { screen in
                let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                return screenNumber == scDisplay.displayID
            }

            let isMain = CGDisplayIsMain(scDisplay.displayID) != 0
            let name = matchingScreen?.localizedName ?? "Display \(scDisplay.displayID)"

            return CaptureDisplay(
                id: scDisplay.displayID,
                scDisplay: scDisplay,
                screen: matchingScreen,
                name: name,
                isMain: isMain,
                frame: matchingScreen?.frame ?? CGRect(x: 0, y: 0, width: scDisplay.width, height: scDisplay.height)
            )
        }
    }

    /// Get the display containing the mouse cursor
    func getDisplayAtCursor() async -> CaptureDisplay? {
        let mouseLocation = NSEvent.mouseLocation
        let displays = await getAvailableDisplays()

        for screen in NSScreen.screens where screen.frame.contains(mouseLocation) {
            return displays.first { $0.screen == screen }
        }

        return displays.first { $0.isMain } ?? displays.first
    }

    // MARK: - Fullscreen Capture

    /// Capture the display at cursor position (default behavior)
    func captureFullscreen() async -> CaptureResult? {
        guard await MainActor.run(body: { !isCaptureFlowActive }) else {
            logger.info("Ignoring fullscreen capture - a selector is already active")
            return nil
        }
        guard let display = await getDisplayAtCursor() else {
            logger.warning("No display available for fullscreen capture")
            return nil
        }
        return await captureDisplay(display)
    }

    /// Capture a specific display
    func captureDisplay(_ display: CaptureDisplay) async -> CaptureResult? {
        guard let cgImage = await captureDisplayCGImage(display) else {
            return nil
        }

        let imageSize = display.screen?.frame.size ?? CGSize(width: display.scDisplay.width, height: display.scDisplay.height)
        return CaptureResult(
            image: NSImage(cgImage: cgImage, size: imageSize),
            preferredScreen: display.screen
        )
    }

    private func captureDisplayCGImage(_ display: CaptureDisplay) async -> CGImage? {
        let scaleFactor = display.scaleFactor
        // Exclude Shotter's own windows (post-capture overlay thumbnail, panels)
        // so they never appear baked into the screenshot.
        let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let ownWindows = availableContent?.windows.filter {
            $0.owningApplication?.processID == ownPID
        } ?? []
        let filter = SCContentFilter(display: display.scDisplay, excludingWindows: ownWindows)
        let config = SCStreamConfiguration()

        config.width = Int(CGFloat(display.scDisplay.width) * scaleFactor)
        config.height = Int(CGFloat(display.scDisplay.height) * scaleFactor)
        config.scalesToFit = false
        config.showsCursor = false

        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            logger.error("Failed to capture display: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Pre-Capture

    func preCaptureScreens() {
        // Skip if a pre-capture is already in flight or recently completed
        guard !isPreCapturing else { return }
        if let ts = preCaptureTimestamp, Date().timeIntervalSince(ts) < Self.preCaptureTimeout {
            return
        }
        isPreCapturing = true
        Task {
            let displays = await getAvailableDisplays()
            var result: [(screen: NSScreen, image: CGImage)] = []
            for display in displays {
                guard let screen = display.screen,
                      let cgImage = await captureDisplayCGImage(display) else {
                    continue
                }
                result.append((screen: screen, image: cgImage))
            }
            nonisolated(unsafe) let captures = result
            let count = captures.count
            await MainActor.run {
                self.preCapturedScreens = captures
                self.preCaptureTimestamp = Date()
                self.isPreCapturing = false
                logger.debug("Pre-captured \(count) screens for frozen capture")
            }
        }
    }

    @MainActor
    private func consumePreCaptures() -> [(screen: NSScreen, image: CGImage)]? {
        guard let captures = preCapturedScreens,
              let timestamp = preCaptureTimestamp,
              Date().timeIntervalSince(timestamp) < Self.preCaptureTimeout else {
            preCapturedScreens = nil
            preCaptureTimestamp = nil
            return nil
        }
        preCapturedScreens = nil
        preCaptureTimestamp = nil
        return captures
    }

    // MARK: - Area Capture

    func captureArea() async -> CaptureResult? {
        guard await beginCaptureFlow() else {
            logger.info("Ignoring area capture - capture already in progress")
            return nil
        }
        defer { endCaptureFlow() }

        let displays = await getAvailableDisplays()
        var screenCaptures: [(screen: NSScreen, image: CGImage)]

        if let cached = await consumePreCaptures() {
            logger.debug("Using pre-captured screens for area capture")
            screenCaptures = cached
        } else {
            screenCaptures = []
            for display in displays {
                guard let screen = display.screen,
                      let cgImage = await captureDisplayCGImage(display) else {
                    continue
                }
                screenCaptures.append((screen: screen, image: cgImage))
            }
        }

        guard !screenCaptures.isEmpty else {
            logger.error("Failed to capture any displays for frozen screen")
            return nil
        }

        let result = await showAreaSelector(screenCaptures: screenCaptures)

        switch result {
        case .area(let areaResult):
            // Crop from pre-captured images instead of re-capturing via ScreenCaptureKit
            let intersecting = displays.filter { display in
                guard let screen = display.screen else { return false }
                return screen.frame.intersects(areaResult.globalRect)
            }
            let capturedDisplays: [(display: CaptureDisplay, image: CGImage)] = intersecting.compactMap { display in
                guard let screenFrame = display.screen?.frame,
                      let capture = screenCaptures.first(where: { $0.screen.frame.origin == screenFrame.origin }) else {
                    return nil
                }
                return (display: display, image: capture.image)
            }

            if let image = composeAreaCapture(from: capturedDisplays, selectionRect: areaResult.globalRect) {
                return CaptureResult(
                    image: image,
                    preferredScreen: preferredScreen(for: areaResult.globalRect, displays: intersecting)
                )
            }

            // Fallback: frozen crop failed, try live capture
            logger.warning("Frozen crop failed, falling back to live capture")
            return await captureArea(in: areaResult.globalRect)
        case .window(let window):
            return await captureWindow(window)
        case .cancelled:
            return nil
        }
    }

    private enum AreaSelectorInternalResult {
        case area(AreaCaptureResult)
        case window(SCWindow)
        case cancelled
    }

    /// Capture an area in global Cocoa coordinates, potentially spanning multiple displays.
    func captureArea(in globalRect: CGRect) async -> CaptureResult? {
        let intersectingDisplays = await getAvailableDisplays().filter { display in
            guard let screen = display.screen else { return false }
            return screen.frame.intersects(globalRect)
        }

        guard !intersectingDisplays.isEmpty else {
            logger.warning("No displays intersect the selected capture area")
            return nil
        }

        var capturedDisplays: [(display: CaptureDisplay, image: CGImage)] = []
        capturedDisplays.reserveCapacity(intersectingDisplays.count)

        for display in intersectingDisplays {
            guard let cgImage = await captureDisplayCGImage(display) else {
                logger.error("Failed to capture display while composing area selection: \(display.name)")
                return nil
            }
            capturedDisplays.append((display: display, image: cgImage))
        }

        guard let image = composeAreaCapture(from: capturedDisplays, selectionRect: globalRect) else {
            logger.error("Failed to compose selected area across displays")
            return nil
        }

        return CaptureResult(
            image: image,
            preferredScreen: preferredScreen(for: globalRect, displays: intersectingDisplays)
        )
    }

    private func composeAreaCapture(
        from displays: [(display: CaptureDisplay, image: CGImage)],
        selectionRect: CGRect
    ) -> NSImage? {
        let maxScale = max(displays.map(\.display.scaleFactor).max() ?? 1.0, 1.0)
        let pixelWidth = max(Int(ceil(selectionRect.width * maxScale)), 1)
        let pixelHeight = max(Int(ceil(selectionRect.height * maxScale)), 1)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        bitmap.size = selectionRect.size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }
        NSGraphicsContext.current = graphicsContext
        NSColor.clear.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: selectionRect.size)).fill()

        for entry in displays {
            guard let screenFrame = entry.display.screen?.frame else { continue }

            let drawRect = CGRect(
                x: screenFrame.minX - selectionRect.minX,
                y: screenFrame.minY - selectionRect.minY,
                width: screenFrame.width,
                height: screenFrame.height
            )

            NSImage(cgImage: entry.image, size: screenFrame.size).draw(
                in: drawRect,
                from: .zero,
                operation: .copy,
                fraction: 1.0
            )
        }

        let image = NSImage(size: selectionRect.size)
        image.addRepresentation(bitmap)
        return image
    }

    private func preferredScreen(for selectionRect: CGRect, displays: [CaptureDisplay]) -> NSScreen? {
        let selectionCenter = CGPoint(x: selectionRect.midX, y: selectionRect.midY)

        if let centeredDisplay = displays.first(where: { display in
            display.screen?.frame.contains(selectionCenter) == true
        }) {
            return centeredDisplay.screen
        }

        return displays.first(where: \.isMain)?.screen ?? displays.first?.screen
    }

    // MARK: - Window Capture

    /// Get all capturable windows
    func getAvailableWindows() async -> [SCWindow] {
        await refreshAvailableContent()

        guard let windows = availableContent?.windows else {
            return []
        }

        let ownBundleID = Bundle.main.bundleIdentifier

        let filteredWindows = windows.filter { window in
            guard let app = window.owningApplication else {
                return false
            }

            if let ownID = ownBundleID, app.bundleIdentifier == ownID {
                return false
            }

            let excludedBundles = ["com.apple.dock", "com.apple.notificationcenterui"]
            if excludedBundles.contains(app.bundleIdentifier) {
                return false
            }

            guard window.frame.width > 50 && window.frame.height > 50 else {
                return false
            }

            let hasTitle = window.title?.isEmpty == false
            let isSystemUI = app.bundleIdentifier.hasPrefix("com.apple.") && window.title == nil

            return hasTitle || !isSystemUI
        }
        return WindowOrdering.sortByZOrder(filteredWindows)
    }

    /// Capture a specific window
    func captureWindow(_ window: SCWindow) async -> CaptureResult? {
        let windowCenter = CGPoint(x: window.frame.midX, y: window.frame.midY)
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let cocoaCenter = NSPoint(x: windowCenter.x, y: mainScreenHeight - windowCenter.y)

        let containingScreen = NSScreen.screens.first { screen in
            screen.frame.contains(cocoaCenter)
        }

        let scaleFactor = containingScreen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()

        config.width = Int(window.frame.width * scaleFactor)
        config.height = Int(window.frame.height * scaleFactor)
        config.scalesToFit = false
        config.showsCursor = false
        config.capturesShadowsOnly = false
        config.shouldBeOpaque = false

        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return CaptureResult(
                image: NSImage(cgImage: image, size: NSSize(width: window.frame.width, height: window.frame.height)),
                preferredScreen: containingScreen
            )
        } catch {
            logger.error("Failed to capture window: \(error.localizedDescription)")
            return nil
        }
    }

    /// Show window picker and capture selected window
    func captureWindowInteractive() async -> CaptureResult? {
        guard await beginCaptureFlow() else {
            logger.info("Ignoring window capture - capture already in progress")
            return nil
        }
        defer { endCaptureFlow() }

        guard let window = await showWindowSelector() else {
            return nil
        }
        return await captureWindow(window)
    }

    // MARK: - Selectors

    @MainActor
    private func showAreaSelector(screenCaptures: [(screen: NSScreen, image: CGImage)]) async -> AreaSelectorInternalResult {
        await withCheckedContinuation { continuation in
            let selector = AreaSelectorWindow(screenCaptures: screenCaptures) { [weak self] result in
                self?.hotkeyManager?.deactivateAreaSelector()
                self?.activeAreaSelector = nil

                switch result {
                case .area(let rect):
                    continuation.resume(returning: .area(AreaCaptureResult(globalRect: rect)))
                case .window(let window):
                    continuation.resume(returning: .window(window))
                case .cancelled:
                    continuation.resume(returning: .cancelled)
                }
            }
            self.activeAreaSelector = selector
            hotkeyManager?.activateAreaSelector(
                onSpace: { [weak selector] in
                    selector?.toggleMode()
                },
                onEscape: { [weak selector] in
                    selector?.cancel()
                }
            )
            selector.show()
        }
    }

    @MainActor
    private func showWindowSelector() async -> SCWindow? {
        await refreshAvailableContent()
        let windows = await getAvailableWindows()

        return await withCheckedContinuation { continuation in
            let selector = WindowSelectorController(windows: windows) { [weak self] window in
                self?.activeWindowSelector = nil
                continuation.resume(returning: window)
            }
            self.activeWindowSelector = selector
            selector.show()
        }
    }
}
