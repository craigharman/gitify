import AppKit
import SwiftUI

@main
struct GitifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var sparkleController = SparkleController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        Settings {
            AppSettingsView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates\u{2026}") {
                    sparkleController.checkForUpdates()
                }
                .disabled(!sparkleController.canCheckForUpdates)
            }
            CommandGroup(after: .newItem) {
                Button("Add Repository…") {
                    Task { await model.promptToAddRepository() }
                }
                .keyboardShortcut("o", modifiers: [.command])
                Button("Scan Folder…") {
                    Task { await model.promptToScanFolder() }
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the Dock/app icon is set even when launched outside the .app bundle
        // (e.g. `swift run`), where Info.plist's CFBundleIconFile doesn't apply.
        // Inside a .app bundle the icon is already set via Info.plist's CFBundleIconFile,
        // so we only attempt this when the SwiftPM resource bundle is available.
        if let url = Bundle.safeModule?.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }
    }
}

extension Bundle {
    /// Returns the SwiftPM resource bundle if it exists, or `nil`.
    /// `Bundle.module` calls `fatalError` when the bundle is missing, so we
    /// replicate its lookup logic without the fatal trap.
    static var safeModule: Bundle? {
        let bundleName = "Gitify_Gitify"
        let candidates = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
        ]
        for candidate in candidates {
            if let url = candidate?.appendingPathComponent(bundleName + ".bundle"),
               let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return nil
    }
}
