import AppKit
import SwiftUI

class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    
    private let onCaptureFullscreen: () -> Void
    private let onCaptureArea: () -> Void
    private let onCaptureWindow: () -> Void
    private let onCaptureDisplay: (CaptureDisplay) -> Void
    private let onOpenSaveFolder: () -> Void
    private let onOpenPreferences: () -> Void
    private let onQuit: () -> Void
    private let getDisplays: () async -> [CaptureDisplay]
    
    init(
        onCaptureFullscreen: @escaping () -> Void,
        onCaptureArea: @escaping () -> Void,
        onCaptureWindow: @escaping () -> Void,
        onCaptureDisplay: @escaping (CaptureDisplay) -> Void,
        onOpenSaveFolder: @escaping () -> Void,
        onOpenPreferences: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        getDisplays: @escaping () async -> [CaptureDisplay]
    ) {
        self.onCaptureFullscreen = onCaptureFullscreen
        self.onCaptureArea = onCaptureArea
        self.onCaptureWindow = onCaptureWindow
        self.onCaptureDisplay = onCaptureDisplay
        self.onOpenSaveFolder = onOpenSaveFolder
        self.onOpenPreferences = onOpenPreferences
        self.onQuit = onQuit
        self.getDisplays = getDisplays
        
        super.init()
        
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Shotter")
            button.image?.isTemplate = true
        }
        
        statusItem?.menu = createMenu()
    }
    
    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        
        // Capture options
        let fullscreenItem = NSMenuItem(
            title: "Capture Fullscreen",
            action: #selector(captureFullscreenClicked),
            keyEquivalent: ""
        )
        fullscreenItem.keyEquivalentModifierMask = [.command, .shift]
        fullscreenItem.keyEquivalent = "3"
        fullscreenItem.target = self
        menu.addItem(fullscreenItem)
        
        let areaItem = NSMenuItem(
            title: "Capture Area",
            action: #selector(captureAreaClicked),
            keyEquivalent: ""
        )
        areaItem.keyEquivalentModifierMask = [.command, .shift]
        areaItem.keyEquivalent = "4"
        areaItem.target = self
        menu.addItem(areaItem)
        
        let windowItem = NSMenuItem(
            title: "Capture Window",
            action: #selector(captureWindowClicked),
            keyEquivalent: ""
        )
        windowItem.keyEquivalentModifierMask = [.command, .shift]
        windowItem.keyEquivalent = "5"
        windowItem.target = self
        menu.addItem(windowItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Capture Display submenu (populated dynamically)
        let displayItem = NSMenuItem(title: "Capture Display", action: nil, keyEquivalent: "")
        displayItem.submenu = NSMenu(title: "Capture Display")
        displayItem.submenu?.delegate = self
        displayItem.tag = 100 // Tag to identify this menu
        menu.addItem(displayItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Open save folder
        let folderItem = NSMenuItem(
            title: "Open Save Folder",
            action: #selector(openSaveFolderClicked),
            keyEquivalent: ""
        )
        folderItem.target = self
        menu.addItem(folderItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Preferences
        let prefsItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(openPreferencesClicked),
            keyEquivalent: ","
        )
        prefsItem.keyEquivalentModifierMask = [.command]
        prefsItem.target = self
        menu.addItem(prefsItem)

        // Check for Updates
        let updateItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdatesClicked),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        // About
        let aboutItem = NSMenuItem(
            title: "About Shotter",
            action: #selector(aboutClicked),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(
            title: "Quit Shotter",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)
        
        return menu
    }
    
    private var displays: [CaptureDisplay] = []
    
    @objc private func captureFullscreenClicked() {
        onCaptureFullscreen()
    }
    
    @objc private func captureAreaClicked() {
        onCaptureArea()
    }
    
    @objc private func captureWindowClicked() {
        onCaptureWindow()
    }
    
    @objc private func captureDisplayClicked(_ sender: NSMenuItem) {
        guard sender.tag < displays.count else { return }
        let display = displays[sender.tag]
        onCaptureDisplay(display)
    }
    
    @objc private func openSaveFolderClicked() {
        onOpenSaveFolder()
    }
    
    @objc private func openPreferencesClicked() {
        onOpenPreferences()
    }

    @objc private func checkForUpdatesClicked() {
        UpdaterController.shared.checkForUpdates()
    }

    @objc private func aboutClicked() {
        let fullVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let version = fullVersion.split(separator: ".").prefix(2).joined(separator: ".")
        let alert = NSAlert()
        alert.messageText = "Shotter v\(version)"
        alert.informativeText = "© 2026 Daniel Ensign\n\ngithub.com/densign01/shotter"
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open GitHub")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let url = URL(string: "https://github.com/densign01/shotter") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func quitClicked() {
        onQuit()
    }
}

extension MenuBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Update display submenu when opened
        if menu.title == "Capture Display" {
            Task {
                let fetchedDisplays = await getDisplays()
                await MainActor.run {
                    self.displays = fetchedDisplays
                    menu.removeAllItems()
                    
                    if fetchedDisplays.isEmpty {
                        let noDisplaysItem = NSMenuItem(title: "No displays found", action: nil, keyEquivalent: "")
                        noDisplaysItem.isEnabled = false
                        menu.addItem(noDisplaysItem)
                    } else {
                        for (index, display) in fetchedDisplays.enumerated() {
                            let title = display.isMain ? "\(display.name) (Main)" : display.name
                            let item = NSMenuItem(
                                title: title,
                                action: #selector(captureDisplayClicked(_:)),
                                keyEquivalent: ""
                            )
                            item.target = self
                            item.tag = index
                            menu.addItem(item)
                        }
                    }
                }
            }
        }
    }
}
