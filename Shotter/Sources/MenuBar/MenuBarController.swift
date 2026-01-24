import AppKit
import SwiftUI

class MenuBarController {
    private var statusItem: NSStatusItem?
    
    private let onCaptureFullscreen: () -> Void
    private let onCaptureArea: () -> Void
    private let onOpenSaveFolder: () -> Void
    private let onOpenPreferences: () -> Void
    
    init(
        onCaptureFullscreen: @escaping () -> Void,
        onCaptureArea: @escaping () -> Void,
        onOpenSaveFolder: @escaping () -> Void,
        onOpenPreferences: @escaping () -> Void
    ) {
        self.onCaptureFullscreen = onCaptureFullscreen
        self.onCaptureArea = onCaptureArea
        self.onOpenSaveFolder = onOpenSaveFolder
        self.onOpenPreferences = onOpenPreferences
        
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
    
    @objc private func captureFullscreenClicked() {
        onCaptureFullscreen()
    }
    
    @objc private func captureAreaClicked() {
        onCaptureArea()
    }
    
    @objc private func openSaveFolderClicked() {
        onOpenSaveFolder()
    }
    
    @objc private func openPreferencesClicked() {
        onOpenPreferences()
    }
    
    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
}
