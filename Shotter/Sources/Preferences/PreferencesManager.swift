import Foundation
import SwiftUI
import ServiceManagement
import Carbon
import os.log

private let logger = Logger(subsystem: "com.densign.shotter", category: "Preferences")

/// Represents a keyboard shortcut configuration
struct ShortcutConfig: Codable, Equatable {
    var keyCode: Int
    var modifiers: Int  // CGEventFlags raw value
    var isEnabled: Bool
    
    var displayString: String {
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: UInt64(modifiers))
        
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        
        // Map key code to character
        let keyChar = keyCodeToString(keyCode)
        parts.append(keyChar)
        
        return parts.joined()
    }
    
    private func keyCodeToString(_ keyCode: Int) -> String {
        let keyMap: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 50: "`", 65: ".", 67: "*", 69: "+",
            71: "Clear", 75: "/", 76: "↩", 78: "-", 81: "=", 82: "0",
            83: "1", 84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7",
            91: "8", 92: "9"
        ]
        return keyMap[keyCode] ?? "?"
    }
    
    /// Default ⌘⇧3 for fullscreen
    static let defaultFullscreen = ShortcutConfig(
        keyCode: 20,  // "3"
        modifiers: Int(CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue),
        isEnabled: true
    )
    
    /// Default ⌘⇧4 for area (Space toggles to window)
    static let defaultArea = ShortcutConfig(
        keyCode: 21,  // "4"
        modifiers: Int(CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue),
        isEnabled: true
    )
    
    /// Default ⌘⇧5 for direct window (disabled by default to match macOS)
    static let defaultWindow = ShortcutConfig(
        keyCode: 23,  // "5"
        modifiers: Int(CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue),
        isEnabled: false  // Disabled by default; users can enable if they want direct window shortcut
    )
}

class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let saveLocation = "saveLocation"
        static let overlayAutoDismissDelay = "overlayAutoDismissDelay"
        static let launchAtLogin = "launchAtLogin"
        static let playCaptureSound = "playCaptureSound"
        static let shortcutFullscreen = "shortcutFullscreen"
        static let shortcutArea = "shortcutArea"
        static let shortcutWindow = "shortcutWindow"
    }
    
    @Published var saveLocation: URL {
        didSet {
            defaults.set(saveLocation.path, forKey: Keys.saveLocation)
        }
    }
    
    @Published var overlayAutoDismissDelay: TimeInterval {
        didSet {
            defaults.set(overlayAutoDismissDelay, forKey: Keys.overlayAutoDismissDelay)
        }
    }
    
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            updateLaunchAtLogin()
        }
    }
    
    @Published var playCaptureSound: Bool {
        didSet {
            defaults.set(playCaptureSound, forKey: Keys.playCaptureSound)
        }
    }
    
    @Published var shortcutFullscreen: ShortcutConfig {
        didSet {
            saveShortcut(shortcutFullscreen, forKey: Keys.shortcutFullscreen)
            NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
        }
    }
    
    @Published var shortcutArea: ShortcutConfig {
        didSet {
            saveShortcut(shortcutArea, forKey: Keys.shortcutArea)
            NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
        }
    }
    
    @Published var shortcutWindow: ShortcutConfig {
        didSet {
            saveShortcut(shortcutWindow, forKey: Keys.shortcutWindow)
            NotificationCenter.default.post(name: .shortcutsDidChange, object: nil)
        }
    }
    
    private func saveShortcut(_ config: ShortcutConfig, forKey key: String) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: key)
        }
    }
    
    private static func loadShortcut(from defaults: UserDefaults, forKey key: String, default defaultConfig: ShortcutConfig) -> ShortcutConfig {
        guard let data = defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(ShortcutConfig.self, from: data) else {
            return defaultConfig
        }
        return config
    }
    
    private init() {
        // Load save location
        if let path = defaults.string(forKey: Keys.saveLocation) {
            saveLocation = URL(fileURLWithPath: path)
        } else {
            // Default: ~/Pictures/Shotter/ with fallback to temp directory
            let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            saveLocation = picturesURL.appendingPathComponent("Shotter")
        }
        
        // Load overlay delay (-1 means never, 0 means not set)
        let delay = defaults.double(forKey: Keys.overlayAutoDismissDelay)
        if delay < 0 {
            overlayAutoDismissDelay = -1.0  // Never auto-dismiss
        } else if delay > 0 {
            overlayAutoDismissDelay = delay
        } else {
            overlayAutoDismissDelay = 5.0   // Default
        }
        
        // Load launch at login
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        
        // Load capture sound preference (default to true)
        if defaults.object(forKey: Keys.playCaptureSound) == nil {
            playCaptureSound = true
        } else {
            playCaptureSound = defaults.bool(forKey: Keys.playCaptureSound)
        }
        
        // Load shortcuts
        shortcutFullscreen = Self.loadShortcut(from: defaults, forKey: Keys.shortcutFullscreen, default: .defaultFullscreen)
        shortcutArea = Self.loadShortcut(from: defaults, forKey: Keys.shortcutArea, default: .defaultArea)
        shortcutWindow = Self.loadShortcut(from: defaults, forKey: Keys.shortcutWindow, default: .defaultWindow)
    }
    
    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Failed to update launch at login: \(error.localizedDescription)")
        }
    }
}

extension Notification.Name {
    static let shortcutsDidChange = Notification.Name("shortcutsDidChange")
}
