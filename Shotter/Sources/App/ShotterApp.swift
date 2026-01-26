import SwiftUI
import AppKit
import os.log

private let logger = Logger(subsystem: "com.densign.shotter", category: "App")

@main
struct ShotterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // No main window - menu bar app only
        Settings {
            PreferencesView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Preferences...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var hotkeyManager: HotkeyManager?
    private var captureEngine: CaptureEngine?
    private var overlayController: OverlayController?
    private var preferencesWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - menu bar only
        NSApp.setActivationPolicy(.accessory)
        
        // Initialize components
        captureEngine = CaptureEngine()
        overlayController = OverlayController()
        
        menuBarController = MenuBarController(
            onCaptureFullscreen: { [weak self] in self?.captureFullscreen() },
            onCaptureArea: { [weak self] in self?.captureArea() },
            onCaptureWindow: { [weak self] in self?.captureWindow() },
            onCaptureDisplay: { [weak self] display in self?.captureDisplay(display) },
            onOpenSaveFolder: { self.openSaveFolder() },
            onOpenPreferences: { self.openPreferences() },
            getDisplays: { [weak self] in
                await self?.captureEngine?.getAvailableDisplays() ?? []
            }
        )
        
        hotkeyManager = HotkeyManager(
            onFullscreen: { [weak self] in self?.captureFullscreen() },
            onArea: { [weak self] in self?.captureArea() },
            onWindow: { [weak self] in self?.captureWindow() }
        )
        
        // Check permissions on launch
        Task {
            await checkPermissions()
        }
    }
    
    private func captureFullscreen() {
        Task {
            guard let image = await captureEngine?.captureFullscreen() else {
                logger.warning("Failed to capture fullscreen")
                return
            }
            handleCapture(image)
        }
    }
    
    private func captureArea() {
        Task {
            guard let image = await captureEngine?.captureArea() else {
                // User cancelled or capture failed - not necessarily an error
                logger.info("Area capture returned nil (user cancelled or failed)")
                return
            }
            handleCapture(image)
        }
    }
    
    private func captureWindow() {
        Task {
            guard let image = await captureEngine?.captureWindowInteractive() else {
                // User cancelled or capture failed
                logger.info("Window capture returned nil (user cancelled or failed)")
                return
            }
            handleCapture(image)
        }
    }
    
    private func captureDisplay(_ display: CaptureDisplay) {
        Task {
            guard let image = await captureEngine?.captureDisplay(display) else {
                logger.warning("Failed to capture display: \(display.name)")
                return
            }
            handleCapture(image)
        }
    }
    
    private func handleCapture(_ image: NSImage) {
        // Play capture sound if enabled
        if PreferencesManager.shared.playCaptureSound {
            SoundManager.shared.playCaptureSound()
        }

        // Auto-copy to clipboard if enabled (must be on main thread for NSPasteboard)
        if PreferencesManager.shared.autoCopyToClipboard {
            DispatchQueue.main.async {
                self.copyToClipboard(image)
            }
        }

        // Save to file
        let result = saveImage(image)
        
        // Show overlay
        DispatchQueue.main.async {
            switch result {
            case .success(let savedURL):
                self.overlayController?.showOverlay(
                    image: image,
                    savedURL: savedURL,
                    onCopy: {
                        self.copyToClipboard(image)
                    },
                    onSave: {
                        NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                    },
                    onAnnotate: {
                        self.overlayController?.dismissOverlay()
                        self.openAnnotationEditor(image: image, savedURL: savedURL)
                    },
                    onDelete: {
                        self.moveToTrash(savedURL)
                    }
                )
            case .failure(let error):
                self.showSaveErrorAlert(error: error)
                // Still show overlay but without save functionality
                self.overlayController?.showOverlay(
                    image: image,
                    savedURL: nil,
                    onCopy: {
                        self.copyToClipboard(image)
                    },
                    onSave: {
                        // Can't show in Finder since save failed
                    },
                    onAnnotate: {
                        self.overlayController?.dismissOverlay()
                        self.openAnnotationEditor(image: image, savedURL: nil)
                    },
                    onDelete: {
                        // No file to delete since save failed
                    }
                )
            }
        }
    }
    
    private enum SaveError: LocalizedError {
        case directoryCreationFailed(Error)
        case imageConversionFailed
        case writeFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .directoryCreationFailed(let error):
                return "Could not create save folder: \(error.localizedDescription)"
            case .imageConversionFailed:
                return "Could not convert image to PNG format"
            case .writeFailed(let error):
                return "Could not save file: \(error.localizedDescription)"
            }
        }
    }
    
    private func saveImage(_ image: NSImage) -> Result<URL, SaveError> {
        let saveFolder = PreferencesManager.shared.saveLocation
        let filename = FileNaming.generateFilename()
        let fileURL = saveFolder.appendingPathComponent(filename)
        
        // Ensure directory exists
        do {
            try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create save directory: \(error.localizedDescription)")
            return .failure(.directoryCreationFailed(error))
        }
        
        // Save as PNG
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            logger.error("Failed to convert image to PNG")
            return .failure(.imageConversionFailed)
        }
        
        do {
            try pngData.write(to: fileURL)
            logger.info("Screenshot saved to: \(fileURL.path)")
            return .success(fileURL)
        } catch {
            logger.error("Failed to write image file: \(error.localizedDescription)")
            return .failure(.writeFailed(error))
        }
    }
    
    private func showSaveErrorAlert(error: SaveError) {
        let alert = NSAlert()
        alert.messageText = "Screenshot Not Saved"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Preferences")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            openPreferences()
        }
    }
    
    private func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    private func moveToTrash(_ fileURL: URL) {
        do {
            try FileManager.default.trashItem(at: fileURL, resultingItemURL: nil)
            logger.info("Screenshot moved to trash: \(fileURL.path)")
        } catch {
            logger.error("Failed to move screenshot to trash: \(error.localizedDescription)")
        }
    }
    
    private func openSaveFolder() {
        NSWorkspace.shared.open(PreferencesManager.shared.saveLocation)
    }
    
    private func openPreferences() {
        if preferencesWindow == nil {
            let prefsView = PreferencesView()
            let hostingController = NSHostingController(rootView: prefsView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Shotter Preferences"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 450, height: 350))
            window.center()
            
            preferencesWindow = window
        }
        
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func openAnnotationEditor(image: NSImage, savedURL: URL?) {
        AnnotationEditorController.shared.openEditor(
            image: image,
            savedURL: savedURL,
            onComplete: { _ in
                // Annotation complete - image was saved
            },
            onCancel: {
                // Annotation cancelled
            }
        )
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
                Permissions.openSystemPreferences(privacy: "Privacy_ScreenCapture")
            } else if needsAccessibility {
                Permissions.openSystemPreferences(privacy: "Privacy_Accessibility")
            }
        }
    }
}
