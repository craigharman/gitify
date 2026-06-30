import AppKit

/// App-level preferences stored in UserDefaults.
enum AppDefaults {

    // MARK: - Keys

    private static let terminalKey = "defaultTerminalBundleID"
    private static let editorKey = "defaultEditorBundleID"
    private static let lastSeenVersionKey = "whatsNew.lastSeenVersion"

    // MARK: - Accessors

    /// The bundle identifier of the preferred terminal app (defaults to Terminal.app).
    static var terminalBundleID: String {
        get { UserDefaults.standard.string(forKey: terminalKey) ?? "com.apple.Terminal" }
        set { UserDefaults.standard.set(newValue, forKey: terminalKey) }
    }

    /// The bundle identifier of the preferred editor app, or `nil` for the system default.
    static var editorBundleID: String? {
        get { UserDefaults.standard.string(forKey: editorKey) }
        set { UserDefaults.standard.set(newValue, forKey: editorKey) }
    }

    /// The app version the user last saw the \u{201c}What\u{2019}s New\u{201d} sheet for.
    static var lastSeenVersion: String? {
        get { UserDefaults.standard.string(forKey: lastSeenVersionKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastSeenVersionKey) }
    }

    /// Resolves a bundle identifier to an application URL, or `nil` if not installed.
    static func appURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).first
    }

    // MARK: - Known apps

    /// A well-known application that Gitify can detect.
    struct KnownApp: Identifiable, Hashable {
        let name: String
        let bundleID: String

        var id: String { bundleID }

        /// Whether this app is currently installed.
        var isInstalled: Bool {
            !NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).isEmpty
        }

        /// The app's icon, if installed.
        var icon: NSImage? {
            guard let url = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).first else { return nil }
            return NSWorkspace.shared.icon(forFile: url.path)
        }
    }

    /// Terminal apps to scan for.
    static let terminalCandidates: [KnownApp] = [
        KnownApp(name: "Terminal",  bundleID: "com.apple.Terminal"),
        KnownApp(name: "iTerm2",    bundleID: "com.googlecode.iterm2"),
        KnownApp(name: "Warp",      bundleID: "dev.warp.Warp-Stable"),
        KnownApp(name: "Ghostty",   bundleID: "com.mitchellh.ghostty"),
        KnownApp(name: "Alacritty", bundleID: "org.alacritty"),
        KnownApp(name: "kitty",     bundleID: "net.kovidgoyal.kitty"),
    ]

    /// Editor apps to scan for.
    static let editorCandidates: [KnownApp] = [
        KnownApp(name: "VS Code",       bundleID: "com.microsoft.VSCode"),
        KnownApp(name: "Xcode",         bundleID: "com.apple.dt.Xcode"),
        KnownApp(name: "Cursor",        bundleID: "com.todesktop.230313mzl4w4u92"),
        KnownApp(name: "Zed",           bundleID: "dev.zed.Zed"),
        KnownApp(name: "Sublime Text",  bundleID: "com.sublimetext.4"),
        KnownApp(name: "Nova",          bundleID: "com.panic.Nova"),
        KnownApp(name: "TextEdit",      bundleID: "com.apple.TextEdit"),
    ]

    /// Returns only the terminal candidates that are currently installed.
    static var installedTerminals: [KnownApp] {
        terminalCandidates.filter(\.isInstalled)
    }

    /// Returns only the editor candidates that are currently installed.
    static var installedEditors: [KnownApp] {
        editorCandidates.filter(\.isInstalled)
    }
}
