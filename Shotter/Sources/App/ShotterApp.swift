import SwiftUI
import AppKit

@main
struct ShotterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // No main window - menu bar app only
        Settings {
            PreferencesView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var hotkeyManager: HotkeyManager?
    private var captureEngine: CaptureEngine?
    private var overlayController: OverlayController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - menu bar only
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize components
        captureEngine = CaptureEngine()
        overlayController = OverlayController()
        
        menuBarController = MenuBarController(
            onCaptureFullscreen: { [weak self] in self?.captureFullscreen() },
            onCaptureArea: { [weak self] in self?.captureArea() },
            onOpenSaveFolder: { self.openSaveFolder() },
            onOpenPreferences: { self.openPreferences() }
        )
        
        hotkeyManager = HotkeyManager(
            onFullscreen: { [weak self] in self?.captureFullscreen() },
            onArea: { [weak self] in self?.captureArea() }
        )
        
        // Check permissions on launch
        Task {
            await checkPermissions()
        }
    }
    
    private func captureFullscreen() {
        Task {
            guard let image = await captureEngine?.captureFullscreen() else {
                print("Failed to capture fullscreen")
                return
            }
            handleCapture(image)
        }
    }
    
    private func captureArea() {
        Task {
            guard let image = await captureEngine?.captureArea() else {
                print("Failed to capture area")
                return
            }
            handleCapture(image)
        }
    }
    
    private func handleCapture(_ image: NSImage) {
        // Save to file
        let savedURL = saveImage(image)
        
        // Show overlay
        DispatchQueue.main.async {
            self.overlayController?.showOverlay(
                image: image,
                savedURL: savedURL,
                onCopy: {
                    self.copyToClipboard(image)
                },
                onSave: {
                    if let url = savedURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                },
                onAnnotate: {
                    // v2: Open annotation editor
                    self.showAnnotateComingSoon()
                }
            )
        }
    }
    
    private func saveImage(_ image: NSImage) -> URL? {
        let saveFolder = PreferencesManager.shared.saveLocation
        let filename = FileNaming.generateFilename()
        let fileURL = saveFolder.appendingPathComponent(filename)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        
        // Save as PNG
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        do {
            try pngData.write(to: fileURL)
            return fileURL
        } catch {
            print("Failed to save image: \(error)")
            return nil
        }
    }
    
    private func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }
    
    private func openSaveFolder() {
        NSWorkspace.shared.open(PreferencesManager.shared.saveLocation)
    }
    
    private func openPreferences() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func showAnnotateComingSoon() {
        let alert = NSAlert()
        alert.messageText = "Coming Soon"
        alert.informativeText = "Annotation tools will be available in Shotter v2."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func checkPermissions() async {
        let hasScreenRecording = await Permissions.checkScreenRecording()
        let hasAccessibility = Permissions.checkAccessibility()
        
        if !hasScreenRecording || !hasAccessibility {
            await MainActor.run {
                self.showPermissionsAlert(
                    needsScreenRecording: !hasScreenRecording,
                    needsAccessibility: !hasAccessibility
                )
            }
        }
    }
    
    private func showPermissionsAlert(needsScreenRecording: Bool, needsAccessibility: Bool) {
        let alert = NSAlert()
        alert.messageText = "Permissions Required"
        
        var message = "Shotter needs additional permissions to work:\n\n"
        if needsScreenRecording {
            message += "• Screen Recording — to capture your screen\n"
        }
        if needsAccessibility {
            message += "• Accessibility — for global keyboard shortcuts\n"
        }
        message += "\nPlease grant these permissions in System Settings."
        
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if needsScreenRecording {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            } else if needsAccessibility {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }
}
