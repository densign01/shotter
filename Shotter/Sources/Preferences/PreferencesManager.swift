import Foundation
import SwiftUI
import ServiceManagement
import os.log

private let logger = Logger(subsystem: "com.densign.shotter", category: "Preferences")

class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let saveLocation = "saveLocation"
        static let overlayAutoDismissDelay = "overlayAutoDismissDelay"
        static let launchAtLogin = "launchAtLogin"
        static let playCaptureSound = "playCaptureSound"
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
