import AppKit
import ScreenCaptureKit

struct Permissions {
    
    // MARK: - Screen Recording
    
    static func checkScreenRecording() async -> Bool {
        do {
            // Attempting to get shareable content will trigger permission prompt if needed
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }
    
    static func requestScreenRecording() async {
        // Try to access screen content - this will trigger the permission dialog
        _ = await checkScreenRecording()
        
        // If still not granted, open System Preferences
        if await !checkScreenRecording() {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
        }
    }
    
    // MARK: - Accessibility
    
    static func checkAccessibility() -> Bool {
        // Check if we have accessibility permissions
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options)
    }
    
    static func requestAccessibility() {
        // This will show the permission prompt
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }
}
