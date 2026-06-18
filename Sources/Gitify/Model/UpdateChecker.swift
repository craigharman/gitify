import Foundation
import AppKit

/// A lightweight self-contained update check against the project's GitHub releases.
///
/// This avoids embedding the Sparkle framework (which needs a hosted appcast, EdDSA signing
/// keys, and Xcode build phases — see docs/RELEASING.md). It checks the latest release tag
/// and, when newer, offers to download the DMG directly.
enum UpdateChecker {
    /// `owner/repo` whose GitHub releases are checked. Update for the real repository.
    static let repository = "craigharman/gitify"

    private struct Asset: Decodable {
        let name: String
        let browserDownloadURL: String
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: String
        let assets: [Asset]
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
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
                let dmgAsset = release.assets.first { $0.name.hasSuffix(".dmg") }
                presentUpdateAvailable(version: latest, dmgAsset: dmgAsset, releaseURL: release.htmlURL)
            } else if userInitiated {
                presentInfo(title: "You're Up to Date",
                            message: "Gitify \(currentVersion) is the latest version.")
            }
        } catch {
            if userInitiated {
                presentInfo(title: "Couldn't Check for Updates",
                            message: error.localizedDescription)
            }
        }
    }

    /// Numeric (semver-aware) comparison: returns true when `candidate` > `current`.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }

    @MainActor
    private static func presentUpdateAvailable(version: String, dmgAsset: Asset?, releaseURL: String) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Gitify \(version) is available (you have \(currentVersion))."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if let asset = dmgAsset, let url = URL(string: asset.browserDownloadURL) {
            downloadDMG(from: url, named: asset.name)
        } else if let url = URL(string: releaseURL) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Downloads the DMG to ~/Downloads and reveals it in Finder on completion.
    private static func downloadDMG(from url: URL, named filename: String) {
        let task = URLSession.shared.downloadTask(with: url) { tempURL, _, error in
            DispatchQueue.main.async {
                guard let tempURL, error == nil else {
                    presentInfo(title: "Download Failed",
                                message: error?.localizedDescription ?? "Unknown error.")
                    return
                }
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                let destination = downloads.appendingPathComponent(filename)
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destination)
                    presentDownloadComplete(file: destination)
                } catch {
                    presentInfo(title: "Download Failed",
                                message: "Could not save to Downloads: \(error.localizedDescription)")
                }
            }
        }
        task.resume()
    }

    @MainActor
    private static func presentDownloadComplete(file: URL) {
        let alert = NSAlert()
        alert.messageText = "Download Complete"
        alert.informativeText = "Gitify has been downloaded to your Downloads folder."
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([file])
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
