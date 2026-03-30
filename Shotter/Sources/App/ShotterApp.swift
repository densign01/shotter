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
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    UpdaterController.shared.checkForUpdates()
                }
                .disabled(!UpdaterController.shared.canCheckForUpdates)
            }
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
        DebugLogger.installSignalHandlers()
        DebugLogger.log("Application did finish launching")

        // Hide dock icon - menu bar only
        NSApp.setActivationPolicy(.accessory)

        // Initialize components
        overlayController = OverlayController()

        menuBarController = MenuBarController(
            onCaptureFullscreen: { [weak self] in self?.captureFullscreen() },
            onCaptureArea: { [weak self] in self?.captureArea() },
            onCaptureWindow: { [weak self] in self?.captureWindow() },
            onCaptureDisplay: { [weak self] display in self?.captureDisplay(display) },
            onOpenSaveFolder: { self.openSaveFolder() },
            onOpenPreferences: { self.openPreferences() },
            onQuit: { [weak self] in self?.requestQuit() },
            getDisplays: { [weak self] in
                await self?.captureEngine?.getAvailableDisplays() ?? []
            }
        )
        
        hotkeyManager = HotkeyManager(
            onFullscreen: { [weak self] directCopy in self?.captureFullscreen(directCopy: directCopy) },
            onArea: { [weak self] directCopy in self?.captureArea(directCopy: directCopy) },
            onWindow: { [weak self] directCopy in self?.captureWindow(directCopy: directCopy) },
            onPotentialCapture: { [weak self] in self?.captureEngine?.preCaptureScreens() }
        )

        captureEngine = CaptureEngine(hotkeyManager: hotkeyManager)
        
        // Check permissions on launch
        Task {
            await checkPermissions()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar app should keep running even when all windows are closed
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Allow all termination requests (Cmd+Q, menu Quit, system shutdown).
        // The cancelOperation overrides in capture/annotation windows prevent
        // Escape from triggering app termination.
        DebugLogger.log("Allowing termination")
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        DebugLogger.log("Application will terminate")
    }

    private func captureFullscreen(directCopy: Bool = false) {
        Task {
            guard let result = await captureEngine?.captureFullscreen() else {
                logger.warning("Failed to capture fullscreen")
                return
            }
            handleCapture(result.image, preferredScreen: result.preferredScreen, directCopy: directCopy)
        }
    }

    private func captureArea(directCopy: Bool = false) {
        Task {
            guard let result = await captureEngine?.captureArea() else {
                // User cancelled or capture failed - not necessarily an error
                logger.info("Area capture returned nil (user cancelled or failed)")
                return
            }
            handleCapture(result.image, preferredScreen: result.preferredScreen, directCopy: directCopy)
        }
    }

    private func captureWindow(directCopy: Bool = false) {
        Task {
            guard let result = await captureEngine?.captureWindowInteractive() else {
                // User cancelled or capture failed
                logger.info("Window capture returned nil (user cancelled or failed)")
                return
            }
            handleCapture(result.image, preferredScreen: result.preferredScreen, directCopy: directCopy)
        }
    }
    
    private func captureDisplay(_ display: CaptureDisplay) {
        Task {
            guard let result = await captureEngine?.captureDisplay(display) else {
                logger.warning("Failed to capture display: \(display.name)")
                return
            }
            handleCapture(result.image, preferredScreen: result.preferredScreen)
        }
    }
    
    private func handleCapture(_ image: NSImage, preferredScreen: NSScreen? = nil, directCopy: Bool = false) {
        let prefs = PreferencesManager.shared

        // Direct-copy mode: Option held + auto-copy is OFF → copy and skip overlay
        let shouldDirectCopy = directCopy && !prefs.autoCopyToClipboard

        // Play capture sound if enabled
        if prefs.playCaptureSound {
            SoundManager.shared.playCaptureSound()
        }

        // When smart file naming is enabled and auto-save is on, use async path
        if prefs.autoSaveScreenshots && prefs.smartFileNaming {
            // Copy immediately (don't wait for OCR)
            if prefs.autoCopyToClipboard || shouldDirectCopy {
                copyToClipboard(image, fileURL: nil)
            }
            if shouldDirectCopy {
                logger.info("Direct-copy mode: copied to clipboard, skipping overlay")
                return
            }

            Task {
                let result = await saveImageAsync(image)
                await MainActor.run {
                    switch result {
                    case .success(let savedURL):
                        self.overlayController?.showOverlay(
                            image: image,
                            savedURL: savedURL,
                            preferredScreen: preferredScreen,
                            onCopy: {
                                self.copyToClipboard(image, fileURL: savedURL)
                            },
                            onSave: {
                                NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                            },
                            onAnnotate: {
                                DebugLogger.log("Overlay annotate clicked (savedURL available)")
                                self.overlayController?.dismissOverlay()
                                self.openAnnotationEditor(image: image, savedURL: savedURL, preferredScreen: preferredScreen)
                            },
                            onDelete: {
                                self.moveToTrash(savedURL)
                            }
                        )
                    case .failure(let error):
                        self.showSaveErrorAlert(error: error)
                        self.showOverlayWithManualSave(image: image, preferredScreen: preferredScreen)
                    }
                }
            }
            return
        }

        // Synchronous path (no smart naming or no auto-save)
        let result: Result<URL, SaveError>?
        let savedURL: URL?
        if prefs.autoSaveScreenshots {
            result = saveImage(image)
            savedURL = try? result?.get()
        } else {
            result = nil
            savedURL = nil
        }

        // Auto-copy to clipboard if enabled (must be on main thread for NSPasteboard)
        // Now includes file URL for terminal compatibility (Ghostty, etc.)
        if prefs.autoCopyToClipboard || shouldDirectCopy {
            DispatchQueue.main.async {
                self.copyToClipboard(image, fileURL: savedURL)
            }
        }

        // Direct-copy mode: skip overlay entirely
        if shouldDirectCopy {
            logger.info("Direct-copy mode: copied to clipboard, skipping overlay")
            return
        }

        // Show overlay
        DispatchQueue.main.async {
            // When auto-save is disabled (no result), show overlay with save functionality
            if result == nil {
                self.showOverlayWithManualSave(image: image, preferredScreen: preferredScreen)
                return
            }

            // Auto-save was attempted - handle success or failure
            switch result! {
            case .success(let savedURL):
                self.overlayController?.showOverlay(
                    image: image,
                    savedURL: savedURL,
                    preferredScreen: preferredScreen,
                    onCopy: {
                        self.copyToClipboard(image, fileURL: savedURL)
                    },
                    onSave: {
                        NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                    },
                    onAnnotate: {
                        DebugLogger.log("Overlay annotate clicked (savedURL available)")
                        self.overlayController?.dismissOverlay()
                        self.openAnnotationEditor(image: image, savedURL: savedURL, preferredScreen: preferredScreen)
                    },
                    onDelete: {
                        self.moveToTrash(savedURL)
                    }
                )
            case .failure(let error):
                self.showSaveErrorAlert(error: error)
                // Auto-save failed - show overlay with manual save option to retry
                self.showOverlayWithManualSave(image: image, preferredScreen: preferredScreen)
            }
        }
    }

    /// Shows overlay with manual save functionality (when auto-save is disabled)
    private func showOverlayWithManualSave(image: NSImage, preferredScreen: NSScreen?) {
        self.overlayController?.showOverlay(
            image: image,
            savedURL: nil,
            preferredScreen: preferredScreen,
            onCopy: {
                self.copyToClipboard(image, fileURL: nil)
            },
            onSave: {
                // Manual save: save the file, then dismiss overlay
                let result = self.saveImage(image)
                switch result {
                case .success(let url):
                    logger.info("Manual save completed: \(url.path)")
                    self.overlayController?.dismissOverlay()
                case .failure(let error):
                    self.showSaveErrorAlert(error: error)
                }
            },
            onAnnotate: {
                DebugLogger.log("Overlay annotate clicked (manual save mode)")
                self.overlayController?.dismissOverlay()
                self.openAnnotationEditor(image: image, savedURL: nil, preferredScreen: preferredScreen)
            },
            onDelete: {
                // No file exists - just discard by dismissing overlay
                logger.info("Discarding unsaved screenshot")
                self.overlayController?.dismissOverlay()
            }
        )
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
    
    /// Async save that uses smart file naming when enabled.
    private func saveImageAsync(_ image: NSImage) async -> Result<URL, SaveError> {
        let prefs = PreferencesManager.shared
        let filename: String
        if prefs.smartFileNaming {
            filename = await SmartFileNaming.generateFilename(for: image)
        } else {
            filename = FileNaming.generateFilename()
        }
        return saveImageWithFilename(image, filename: filename)
    }

    private func saveImage(_ image: NSImage) -> Result<URL, SaveError> {
        let filename = FileNaming.generateFilename()
        return saveImageWithFilename(image, filename: filename)
    }

    private func saveImageWithFilename(_ image: NSImage, filename: String) -> Result<URL, SaveError> {
        let saveFolder = PreferencesManager.shared.saveLocation
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
    
    /// Copies an image to the clipboard with formats optimized for terminal apps (Ghostty, etc.)
    /// - Parameters:
    ///   - image: The image to copy
    ///   - fileURL: Optional file URL - when provided, terminals can display the image inline
    private func copyToClipboard(_ image: NSImage, fileURL: URL? = nil) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // Declare types we'll provide (order matters - most preferred first)
        var types: [NSPasteboard.PasteboardType] = [.png, .tiff]
        if fileURL != nil {
            types.insert(.fileURL, at: 0)
        }
        pasteboard.declareTypes(types, owner: nil)

        // Write file URL first (enables terminal apps like Ghostty to display images inline)
        if let fileURL = fileURL {
            pasteboard.setString(fileURL.absoluteString, forType: .fileURL)
        }

        // Write PNG data explicitly (preferred by most apps)
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            pasteboard.setData(pngData, forType: .png)
        }

        // Write TIFF data for apps that prefer it
        if let tiffData = image.tiffRepresentation {
            pasteboard.setData(tiffData, forType: .tiff)
        }
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
        let saveLocation = PreferencesManager.shared.saveLocation

        do {
            try FileManager.default.createDirectory(at: saveLocation, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create save directory before opening: \(error.localizedDescription)")
        }

        NSWorkspace.shared.open(saveLocation)
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

    private func requestQuit() {
        DebugLogger.log("User requested quit")
        NSApp.terminate(nil)
    }
    
    private func openAnnotationEditor(image: NSImage, savedURL: URL?, preferredScreen: NSScreen?) {
        DebugLogger.log("Opening annotation editor; savedURL=\(savedURL?.path ?? "nil"), preferredScreen=\(preferredScreen?.localizedName ?? "nil")")
        AnnotationEditorController.shared.openEditor(
            image: image,
            savedURL: savedURL,
            preferredScreen: preferredScreen,
            onComplete: { _ in
                // Annotation complete - image was saved
                DebugLogger.log("Annotation editor completed")
            },
            onCancel: {
                // Annotation cancelled
                DebugLogger.log("Annotation editor cancelled")
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

        if needsScreenRecording && needsAccessibility {
            alert.addButton(withTitle: "Open Screen Recording")
            alert.addButton(withTitle: "Open Accessibility")
            alert.addButton(withTitle: "Later")
        } else {
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
        }

        let response = alert.runModal()
        if needsScreenRecording && needsAccessibility {
            if response == .alertFirstButtonReturn {
                Permissions.openSystemPreferences(privacy: "Privacy_ScreenCapture")
            } else if response == .alertSecondButtonReturn {
                Permissions.openSystemPreferences(privacy: "Privacy_Accessibility")
            }
        } else if response == .alertFirstButtonReturn {
            if needsScreenRecording {
                Permissions.openSystemPreferences(privacy: "Privacy_ScreenCapture")
            } else if needsAccessibility {
                Permissions.openSystemPreferences(privacy: "Privacy_Accessibility")
            }
        }
    }
}
