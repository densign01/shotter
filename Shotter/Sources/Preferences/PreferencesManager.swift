import Foundation
import SwiftUI
import ServiceManagement

class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let saveLocation = "saveLocation"
        static let overlayAutoDismissDelay = "overlayAutoDismissDelay"
        static let launchAtLogin = "launchAtLogin"
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
    
    private init() {
        // Load save location
        if let path = defaults.string(forKey: Keys.saveLocation) {
            saveLocation = URL(fileURLWithPath: path)
        } else {
            // Default: ~/Pictures/Shotter/
            let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
            saveLocation = picturesURL.appendingPathComponent("Shotter")
        }
        
        // Load overlay delay
        let delay = defaults.double(forKey: Keys.overlayAutoDismissDelay)
        overlayAutoDismissDelay = delay > 0 ? delay : 5.0
        
        // Load launch at login
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
    }
    
    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }
}
