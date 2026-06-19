import Sparkle

/// Manages the Sparkle auto-updater lifecycle.
///
/// `SPUStandardUpdaterController` must be created and used on the main thread,
/// so the entire class is confined to `@MainActor`.
@MainActor
final class SparkleController {
    private let updaterController: SPUStandardUpdaterController

    /// Whether the \u{201c}Check for Updates\u{2026}\u{201d} menu item should be enabled.
    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        
        // Quiet check on launch; surfaces a prompt only if a newer version exists.
        updaterController.updater.checkForUpdatesInBackground()
    }

    /// Manually trigger an update check (from the menu bar).
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
