import Sparkle
import AppKit

/// Controller for Sparkle auto-updates.
/// Manages the SPUUpdater instance and provides a "Check for Updates" action.
final class UpdaterController {
    static let shared = UpdaterController()

    private let updaterController: SPUStandardUpdaterController

    private init() {
        // Create the standard updater controller which handles all UI
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// The underlying SPUUpdater for advanced control
    var updater: SPUUpdater {
        updaterController.updater
    }

    /// Check for updates (user-initiated)
    @objc func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Whether the updater can check for updates right now
    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }
}
