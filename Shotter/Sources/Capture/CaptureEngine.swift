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

/// Result of area selection, including which display was selected
struct AreaCaptureResult {
    let rect: CGRect
    let display: CaptureDisplay
}

/// Result of window selection
struct WindowSelectionResult {
    let window: SCWindow
    let display: CaptureDisplay
}

class CaptureEngine {
    private var availableContent: SCShareableContent?

    // Retain selectors to prevent deallocation while showing
    private var activeAreaSelector: AreaSelectorWindow?
    private var activeWindowSelector: WindowSelectorController?

    init() {
        Task {
            await refreshAvailableContent()
        }
    }
    
    private func refreshAvailableContent() async {
        do {
            availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
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
            // Find matching NSScreen
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
                frame: CGRect(x: 0, y: 0, width: scDisplay.width, height: scDisplay.height)
            )
        }
    }
    
    /// Get the display containing the mouse cursor
    func getDisplayAtCursor() async -> CaptureDisplay? {
        let mouseLocation = NSEvent.mouseLocation
        let displays = await getAvailableDisplays()
        
        // Find the screen containing the mouse
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                return displays.first { $0.screen == screen }
            }
        }
        
        // Fallback to main display
        return displays.first { $0.isMain } ?? displays.first
    }
    
    // MARK: - Fullscreen Capture
    
    /// Capture the display at cursor position (default behavior)
    func captureFullscreen() async -> NSImage? {
        guard let display = await getDisplayAtCursor() else {
            logger.warning("No display available for fullscreen capture")
            return nil
        }
        return await captureDisplay(display)
    }
    
    /// Capture a specific display
    func captureDisplay(_ display: CaptureDisplay) async -> NSImage? {
        let scaleFactor = display.scaleFactor
        let filter = SCContentFilter(display: display.scDisplay, excludingWindows: [])
        let config = SCStreamConfiguration()
        
        config.width = Int(CGFloat(display.scDisplay.width) * scaleFactor)
        config.height = Int(CGFloat(display.scDisplay.height) * scaleFactor)
        config.scalesToFit = false
        config.showsCursor = false
        
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return NSImage(cgImage: image, size: NSSize(width: display.scDisplay.width, height: display.scDisplay.height))
        } catch {
            logger.error("Failed to capture display: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Area Capture
    
    func captureArea() async -> NSImage? {
        // Show selection overlay and wait for user to select area (or window via Space)
        let result = await showAreaSelector()
        
        switch result {
        case .area(let areaResult):
            return await captureAreaOnDisplay(rect: areaResult.rect, display: areaResult.display)
        case .window(let window):
            return await captureWindow(window)
        case .cancelled:
            return nil
        }
    }
    
    /// Internal result type for area selector
    private enum AreaSelectorInternalResult {
        case area(AreaCaptureResult)
        case window(SCWindow)
        case cancelled
    }
    
    /// Capture a specific area on a specific display
    func captureAreaOnDisplay(rect: CGRect, display: CaptureDisplay) async -> NSImage? {
        let scaleFactor = display.scaleFactor
        let filter = SCContentFilter(display: display.scDisplay, excludingWindows: [])
        let config = SCStreamConfiguration()
        
        config.width = Int(CGFloat(display.scDisplay.width) * scaleFactor)
        config.height = Int(CGFloat(display.scDisplay.height) * scaleFactor)
        config.scalesToFit = false
        config.showsCursor = false
        
        do {
            let fullImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            
            // Scale rect for display scale factor
            let scaledRect = CGRect(
                x: rect.origin.x * scaleFactor,
                y: rect.origin.y * scaleFactor,
                width: rect.width * scaleFactor,
                height: rect.height * scaleFactor
            )
            
            guard let croppedCGImage = fullImage.cropping(to: scaledRect) else {
                logger.error("Failed to crop image to selected area")
                return nil
            }
            
            return NSImage(
                cgImage: croppedCGImage,
                size: NSSize(width: rect.width, height: rect.height)
            )
        } catch {
            logger.error("Failed to capture area: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Window Capture
    
    /// Get all capturable windows
    func getAvailableWindows() async -> [SCWindow] {
        await refreshAvailableContent()
        
        guard let windows = availableContent?.windows else {
            return []
        }
        
        // Filter out system windows and tiny windows
        return windows.filter { window in
            // Must have a reasonable size
            guard window.frame.width > 50 && window.frame.height > 50 else {
                return false
            }
            
            // Must have a title or be from a non-system app
            let hasTitle = window.title?.isEmpty == false
            let isSystemUI = (window.owningApplication?.bundleIdentifier.hasPrefix("com.apple.") ?? false)
                && window.title == nil
            
            return hasTitle || !isSystemUI
        }
    }
    
    /// Capture a specific window
    func captureWindow(_ window: SCWindow) async -> NSImage? {
        // Find which screen contains the window center
        let windowCenter = CGPoint(x: window.frame.midX, y: window.frame.midY)

        // ScreenCaptureKit uses top-left origin, Cocoa uses bottom-left origin
        // Convert SCK coordinates to Cocoa coordinates
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let cocoaCenter = NSPoint(x: windowCenter.x, y: mainScreenHeight - windowCenter.y)

        // Find the screen containing this point
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
            return NSImage(cgImage: image, size: NSSize(width: window.frame.width, height: window.frame.height))
        } catch {
            logger.error("Failed to capture window: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Show window picker and capture selected window
    func captureWindowInteractive() async -> NSImage? {
        guard let window = await showWindowSelector() else {
            return nil
        }
        return await captureWindow(window)
    }
    
    // MARK: - Selectors
    
    @MainActor
    private func showAreaSelector() async -> AreaSelectorInternalResult {
        return await withCheckedContinuation { continuation in
            let selector = AreaSelectorWindow { [weak self] result in
                // Release the selector now that we're done
                self?.activeAreaSelector = nil

                switch result {
                case .area(let rect, let screen):
                    // Find the matching CaptureDisplay
                    Task {
                        let allDisplays = await self?.getAvailableDisplays() ?? []
                        if let display = allDisplays.first(where: { $0.screen == screen }) {
                            continuation.resume(returning: .area(AreaCaptureResult(rect: rect, display: display)))
                        } else {
                            continuation.resume(returning: .cancelled)
                        }
                    }
                case .window(let window):
                    continuation.resume(returning: .window(window))
                case .cancelled:
                    continuation.resume(returning: .cancelled)
                }
            }
            // Retain the selector to prevent deallocation
            self.activeAreaSelector = selector
            selector.show()
        }
    }
    
    @MainActor
    private func showWindowSelector() async -> SCWindow? {
        await refreshAvailableContent()
        let windows = await getAvailableWindows()

        return await withCheckedContinuation { continuation in
            let selector = WindowSelectorController(windows: windows) { [weak self] window in
                // Release the selector now that we're done
                self?.activeWindowSelector = nil
                continuation.resume(returning: window)
            }
            // Retain the selector to prevent deallocation
            self.activeWindowSelector = selector
            selector.show()
        }
    }
}
