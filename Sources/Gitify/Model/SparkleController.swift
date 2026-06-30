import Sparkle

/// Manages the Sparkle auto-updater lifecycle.
///
/// `SPUStandardUpdaterController` must be created and used on the main thread,
/// so the entire class is confined to `@MainActor`.
@MainActor @Observable
final class SparkleController {
    private let updaterController: SPUStandardUpdaterController
    private var observation: NSKeyValueObservation?

    /// Whether the \u{201c}Check for Updates\u{2026}\u{201d} menu item should be enabled.
    private(set) var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        observation = updaterController.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] updater, _ in
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }

        // Quiet check on launch; surfaces a prompt only if a newer version exists.
        updaterController.updater.checkForUpdatesInBackground()
    }

    /// Manually trigger an update check (from the menu bar).
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
