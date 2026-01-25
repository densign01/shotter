import AppKit
import ScreenCaptureKit
import os.log

private let logger = Logger(subsystem: "com.densign.shotter", category: "Permissions")

struct Permissions {

    // MARK: - Cached State

    private static var cachedScreenRecording: Bool?
    private static var cachedAccessibility: Bool?
    private static var lastScreenRecordingCheck: Date?
    private static var lastAccessibilityCheck: Date?
    private static let cacheInterval: TimeInterval = 30 // Refresh every 30 seconds

    // MARK: - Screen Recording

    static func checkScreenRecording() async -> Bool {
        // Return cached value if recent
        if let cached = cachedScreenRecording,
           let lastCheck = lastScreenRecordingCheck,
           Date().timeIntervalSince(lastCheck) < cacheInterval {
            return cached
        }

        do {
            // Attempting to get shareable content will trigger permission prompt if needed
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            cachedScreenRecording = true
            lastScreenRecordingCheck = Date()
            return true
        } catch {
            cachedScreenRecording = false
            lastScreenRecordingCheck = Date()
            return false
        }
    }
    
    static func requestScreenRecording() async {
        // Try to access screen content - this will trigger the permission dialog
        _ = await checkScreenRecording()
        
        // If still not granted, open System Preferences
        if await !checkScreenRecording() {
            await MainActor.run {
                openSystemPreferences(privacy: "Privacy_ScreenCapture")
            }
        }
    }
    
    // MARK: - Accessibility
    
    static func checkAccessibility() -> Bool {
        // Return cached value if recent
        if let cached = cachedAccessibility,
           let lastCheck = lastAccessibilityCheck,
           Date().timeIntervalSince(lastCheck) < cacheInterval {
            return cached
        }

        // Check if we have accessibility permissions
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let result = AXIsProcessTrustedWithOptions(options)
        cachedAccessibility = result
        lastAccessibilityCheck = Date()
        return result
    }
    
    static func requestAccessibility() {
        // This will show the permission prompt
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Helpers
    
    static func openSystemPreferences(privacy: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(privacy)") else {
            logger.error("Failed to create system preferences URL for: \(privacy)")
            return
        }
        NSWorkspace.shared.open(url)
    }
    
    static func invalidateCache() {
        cachedScreenRecording = nil
        cachedAccessibility = nil
        lastScreenRecordingCheck = nil
        lastAccessibilityCheck = nil
    }
}
