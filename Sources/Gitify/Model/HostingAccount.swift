import Foundation

/// A GitHub/GitLab account authenticated with a personal access token (stored in Keychain).
struct HostingAccount: Identifiable, Codable, Hashable {
    enum Provider: String, Codable, CaseIterable, Identifiable {
        case github, gitlab
        var id: String { rawValue }
        var displayName: String { self == .github ? "GitHub" : "GitLab" }
        var apiBase: String { self == .github ? "https://api.github.com" : "https://gitlab.com/api/v4" }
    }

    let provider: Provider
    let login: String
    var id: String { "\(provider.rawValue):\(login)" }
}

/// A repository returned by a provider's API.
struct HostedRepo: Identifiable, Hashable {
    let id: String
    let fullName: String
    let cloneURL: String
    let isPrivate: Bool
}

/// Persists the list of accounts (metadata only; tokens live in the Keychain).
struct AccountStore {
    private let fileURL: URL

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gitify", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("accounts.json")
    }

    func load() -> [HostingAccount] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([HostingAccount].self, from: data)) ?? []
    }

    func save(_ accounts: [HostingAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
