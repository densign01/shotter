import AppKit
import ScreenCaptureKit
import os.log

private let logger = Logger(subsystem: "com.densign.shotter", category: "Capture")

class CaptureEngine {
    private var availableContent: SCShareableContent?
    
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
    
    /// Get the actual display scale factor
    private func getDisplayScaleFactor() -> CGFloat {
        return NSScreen.main?.backingScaleFactor ?? 2.0
    }
    
    // MARK: - Fullscreen Capture
    
    func captureFullscreen() async -> NSImage? {
        await refreshAvailableContent()
        
        guard let display = availableContent?.displays.first else {
            logger.warning("No display available for fullscreen capture")
            return nil
        }
        
        let scaleFactor = getDisplayScaleFactor()
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        
        config.width = Int(CGFloat(display.width) * scaleFactor)
        config.height = Int(CGFloat(display.height) * scaleFactor)
        config.scalesToFit = false
        config.showsCursor = false
        
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return NSImage(cgImage: image, size: NSSize(width: display.width, height: display.height))
        } catch {
            logger.error("Failed to capture fullscreen: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Area Capture
    
    func captureArea() async -> NSImage? {
        // Show selection overlay and wait for user to select area
        guard let selectedRect = await showAreaSelector() else {
            return nil
        }
        
        await refreshAvailableContent()
        
        guard let display = availableContent?.displays.first else {
            logger.warning("No display available for area capture")
            return nil
        }
        
        let scaleFactor = getDisplayScaleFactor()
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        
        config.width = Int(CGFloat(display.width) * scaleFactor)
        config.height = Int(CGFloat(display.height) * scaleFactor)
        config.scalesToFit = false
        config.showsCursor = false
        
        // Capture full screen first, then crop
        do {
            let fullImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            
            // Scale selectedRect for display scale factor
            let scaledRect = CGRect(
                x: selectedRect.origin.x * scaleFactor,
                y: selectedRect.origin.y * scaleFactor,
                width: selectedRect.width * scaleFactor,
                height: selectedRect.height * scaleFactor
            )
            
            // Crop to selected area
            guard let croppedCGImage = fullImage.cropping(to: scaledRect) else {
                logger.error("Failed to crop image to selected area")
                return nil
            }
            
            return NSImage(
                cgImage: croppedCGImage,
                size: NSSize(width: selectedRect.width, height: selectedRect.height)
            )
        } catch {
            logger.error("Failed to capture area: \(error.localizedDescription)")
            return nil
        }
    }
    
    @MainActor
    private func showAreaSelector() async -> CGRect? {
        return await withCheckedContinuation { continuation in
            let selector = AreaSelectorWindow { rect in
                continuation.resume(returning: rect)
            }
            selector.show()
        }
    }
}
