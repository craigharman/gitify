import Foundation
import AppKit
import GitKit

/// Top-level application state: the list of repositories and the current selection.
@MainActor
@Observable
final class AppModel {
    private(set) var repositories: [RepositoryRef]
    var selectedRepositoryID: RepositoryRef.ID? {
        didSet { persistSelection() }
    }

    /// UserDefaults key for the last-opened repository, restored on launch.
    private static let lastSelectedKey = "lastSelectedRepositoryID"

    // Clone progress state, surfaced as an overlay while a clone runs.
    private(set) var cloneProgress: String?
    var isCloning: Bool { cloneProgress != nil }

    // Hosting accounts (GitHub/GitLab) authenticated by personal access token.
    private(set) var accounts: [HostingAccount]

    private let store = RepositoryStore()
    private let accountStore = AccountStore()

    init() {
        repositories = store.load()
        accounts = accountStore.load()
        // Restore the repository open in the previous session if it still exists,
        // otherwise fall back to the first in the list.
        let savedID = UserDefaults.standard.string(forKey: Self.lastSelectedKey)
            .flatMap(UUID.init(uuidString:))
        selectedRepositoryID = repositories.first { $0.id == savedID }?.id
            ?? repositories.first?.id
    }

    /// Saves the current selection so it can be reopened on the next launch.
    private func persistSelection() {
        let defaults = UserDefaults.standard
        if let id = selectedRepositoryID {
            defaults.set(id.uuidString, forKey: Self.lastSelectedKey)
        } else {
            defaults.removeObject(forKey: Self.lastSelectedKey)
        }
    }

    // MARK: - Hosting accounts

    /// Validates a token, stores it in the Keychain, and adds the account.
    func addAccount(provider: HostingAccount.Provider, token: String) async throws {
        let login = try await HostingClient.validate(provider: provider, token: token)
        let account = HostingAccount(provider: provider, login: login)
        Keychain.set(token, account: account.id)
        if !accounts.contains(account) {
            accounts.append(account)
            accountStore.save(accounts)
        }
    }

    func removeAccount(_ account: HostingAccount) {
        Keychain.delete(account: account.id)
        accounts.removeAll { $0.id == account.id }
        accountStore.save(accounts)
    }

    func repositories(for account: HostingAccount) async throws -> [HostedRepo] {
        guard let token = Keychain.get(account: account.id) else {
            throw HostingClient.ClientError(message: "No stored token for \(account.login).")
        }
        return try await HostingClient.repositories(provider: account.provider, token: token)
    }

    /// Clones a hosted repository using an authenticated HTTPS URL.
    func clone(_ repo: HostedRepo, account: HostingAccount) async {
        guard !isCloning else { return }
        guard let parent = Prompt.chooseDirectory(prompt: "Clone Here",
                                                  message: "Choose where to clone \(repo.fullName)") else { return }
        let token = Keychain.get(account: account.id)
        let url = Self.authenticatedURL(repo.cloneURL, provider: account.provider, token: token)
        cloneProgress = "Starting…"
        defer { cloneProgress = nil }
        let progress: @Sendable (String) -> Void = { [weak self] line in
            Task { @MainActor in self?.cloneProgress = line }
        }
        do {
            let dest = try await CLIGitService.clone(url: url, into: parent,
                                                     name: repo.fullName.split(separator: "/").last.map(String.init),
                                                     onProgress: progress)
            await add(directory: dest)
        } catch {
            presentError("Clone failed: \(error)")
        }
    }

    /// Embeds the token into an HTTPS clone URL so private repos can be cloned non-interactively.
    private static func authenticatedURL(_ clone: String, provider: HostingAccount.Provider, token: String?) -> String {
        guard let token, clone.hasPrefix("https://") else { return clone }
        let body = String(clone.dropFirst("https://".count))
        let user = provider == .github ? token : "oauth2:\(token)"
        return "https://\(user)@\(body)"
    }

    var selectedRepository: RepositoryRef? {
        repositories.first { $0.id == selectedRepositoryID }
    }

    /// Presents an open panel and adds the chosen directory if it is a git repository.
    func promptToAddRepository() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Repository"
        panel.message = "Choose a Git repository folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await add(directory: url)
    }

    /// Adds a directory, resolving it to the repository root first.
    func add(directory: URL) async {
        guard let root = await CLIGitService.repositoryRoot(for: directory) else {
            presentError("\(url: directory) is not a Git repository.")
            return
        }
        guard !repositories.contains(where: { $0.path == root.path }) else {
            selectedRepositoryID = repositories.first { $0.path == root.path }?.id
            return
        }
        let ref = RepositoryRef(path: root.path)
        repositories.append(ref)
        store.save(repositories)
        selectedRepositoryID = ref.id
    }

    /// Prompts for a URL and destination, clones, and adds the result.
    func promptToClone() async {
        guard !isCloning else { return }
        guard let url = Prompt.text(title: "Clone Repository",
                                    message: "Enter a Git URL (https or ssh).",
                                    confirm: "Choose Location…") else { return }
        guard let parent = Prompt.chooseDirectory(prompt: "Clone Here",
                                                  message: "Choose where to clone the repository") else { return }
        cloneProgress = "Starting…"
        defer { cloneProgress = nil }

        let progress: @Sendable (String) -> Void = { [weak self] line in
            Task { @MainActor in self?.cloneProgress = line }
        }
        do {
            let dest = try await CLIGitService.clone(url: url, into: parent, onProgress: progress)
            await add(directory: dest)
        } catch {
            presentError("Clone failed: \(error)")
        }
    }

    func remove(_ ref: RepositoryRef) {
        repositories.removeAll { $0.id == ref.id }
        store.save(repositories)
        // Discard the repository's persisted sidebar state so it doesn't linger in UserDefaults.
        SidebarDefaults.removeAll(for: ref.path)
        if selectedRepositoryID == ref.id {
            selectedRepositoryID = repositories.first?.id
        }
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t add repository"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private extension String.StringInterpolation {
    mutating func appendInterpolation(url: URL) {
        appendLiteral(url.lastPathComponent)
    }
}
