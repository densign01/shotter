import AppKit
import ScreenCaptureKit

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
            print("Failed to get available content: \(error)")
        }
    }
    
    // MARK: - Fullscreen Capture
    
    func captureFullscreen() async -> NSImage? {
        await refreshAvailableContent()
        
        guard let display = availableContent?.displays.first else {
            print("No display available")
            return nil
        }
        
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        
        config.width = display.width * 2  // Retina
        config.height = display.height * 2
        config.scalesToFit = false
        config.showsCursor = false
        
        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return NSImage(cgImage: image, size: NSSize(width: display.width, height: display.height))
        } catch {
            print("Failed to capture fullscreen: \(error)")
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
            print("No display available")
            return nil
        }
        
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        
        config.width = display.width * 2  // Retina
        config.height = display.height * 2
        config.scalesToFit = false
        config.showsCursor = false
        
        // Capture full screen first, then crop
        do {
            let fullImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            
            // Scale selectedRect for Retina
            let scale = CGFloat(display.width * 2) / CGFloat(display.width)
            let scaledRect = CGRect(
                x: selectedRect.origin.x * scale,
                y: selectedRect.origin.y * scale,
                width: selectedRect.width * scale,
                height: selectedRect.height * scale
            )
            
            // Crop to selected area
            guard let croppedCGImage = fullImage.cropping(to: scaledRect) else {
                return nil
            }
            
            return NSImage(
                cgImage: croppedCGImage,
                size: NSSize(width: selectedRect.width, height: selectedRect.height)
            )
        } catch {
            print("Failed to capture area: \(error)")
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
