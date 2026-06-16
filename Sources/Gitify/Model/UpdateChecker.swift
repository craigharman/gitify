import Foundation
import AppKit

/// A lightweight self-contained update check against the project's GitHub releases.
///
/// This avoids embedding the Sparkle framework (which needs a hosted appcast, EdDSA signing
/// keys, and Xcode build phases — see docs/RELEASING.md). It checks the latest release tag
/// and, when newer, offers to open the download page.
enum UpdateChecker {
    /// `owner/repo` whose GitHub releases are checked. Update for the real repository.
    static let repository = "craigharman/gitify"

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Checks for a newer release. When `userInitiated`, also reports "up to date" / errors.
    @MainActor
    static func checkForUpdates(userInitiated: Bool) async {
        do {
            let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))

            if isNewer(latest, than: currentVersion) {
                presentUpdateAvailable(version: latest, urlString: release.htmlURL)
            } else if userInitiated {
                presentInfo(title: "You’re Up to Date",
                            message: "Gitify \(currentVersion) is the latest version.")
            }
        } catch {
            if userInitiated {
                presentInfo(title: "Couldn’t Check for Updates",
                            message: error.localizedDescription)
            }
        }
    }

    /// Numeric (semver-aware) comparison: returns true when `candidate` > `current`.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }

    @MainActor
    private static func presentUpdateAvailable(version: String, urlString: String) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Gitify \(version) is available (you have \(currentVersion))."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    private static func presentInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
