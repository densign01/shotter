import AppKit
import CoreGraphics
import ScreenCaptureKit
import os.log

private let logger = Logger(subsystem: "com.densign.shotter", category: "Permissions")

struct Permissions {

    // MARK: - Cached State

    // The cache is read from the CGEvent tap thread and written from async
    // tasks — all access goes through cacheLock.
    private static let cacheLock = NSLock()
    private static var cachedScreenRecording: Bool?
    private static var cachedAccessibility: Bool?
    private static var lastScreenRecordingCheck: Date?
    private static var lastAccessibilityCheck: Date?
    private static let cacheInterval: TimeInterval = 30 // Refresh every 30 seconds

    private static func cachedValue(_ value: Bool?, lastCheck: Date?) -> Bool? {
        guard let value, let lastCheck,
              Date().timeIntervalSince(lastCheck) < cacheInterval else {
            return nil
        }
        return value
    }

    // MARK: - Screen Recording

    static func checkScreenRecording() async -> Bool {
        if checkScreenRecordingSync() {
            return true
        }

        // Return cached value if recent
        if let cached = cachedScreenRecordingValue() {
            return cached
        }

        do {
            // Attempting to get shareable content will trigger permission prompt if needed
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            storeScreenRecordingResult(true)
            return true
        } catch {
            storeScreenRecordingResult(false)
            return false
        }
    }

    /// Synchronous locked read of the screen-recording cache (async-context safe).
    private static func cachedScreenRecordingValue() -> Bool? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedValue(cachedScreenRecording, lastCheck: lastScreenRecordingCheck)
    }

    static func checkScreenRecordingSync(forceRefresh: Bool = false) -> Bool {
        if !forceRefresh {
            cacheLock.lock()
            let cached = cachedValue(cachedScreenRecording, lastCheck: lastScreenRecordingCheck)
            cacheLock.unlock()
            if let cached {
                return cached
            }
        }

        let result = CGPreflightScreenCaptureAccess()
        storeScreenRecordingResult(result)
        return result
    }

    private static func storeScreenRecordingResult(_ result: Bool) {
        cacheLock.lock()
        cachedScreenRecording = result
        lastScreenRecordingCheck = Date()
        cacheLock.unlock()
    }
    
    static func requestScreenRecording() async {
        // Try to access screen content - this will trigger the permission dialog
        _ = await checkScreenRecording()

        invalidateCache()

        // If still not granted, open System Preferences
        if !checkScreenRecordingSync(forceRefresh: true) {
            await MainActor.run {
                openSystemPreferences(privacy: "Privacy_ScreenCapture")
            }
        }
    }
    
    // MARK: - Accessibility
    
    static func checkAccessibility() -> Bool {
        // Return cached value if recent
        cacheLock.lock()
        let cached = cachedValue(cachedAccessibility, lastCheck: lastAccessibilityCheck)
        cacheLock.unlock()
        if let cached {
            return cached
        }

        // Check if we have accessibility permissions
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let result = AXIsProcessTrustedWithOptions(options)
        cacheLock.lock()
        cachedAccessibility = result
        lastAccessibilityCheck = Date()
        cacheLock.unlock()
        return result
    }
    
    static func requestAccessibility() {
        // This will show the permission prompt
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
        invalidateCache()
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
        cacheLock.lock()
        cachedScreenRecording = nil
        cachedAccessibility = nil
        lastScreenRecordingCheck = nil
        lastAccessibilityCheck = nil
        cacheLock.unlock()
    }
}
