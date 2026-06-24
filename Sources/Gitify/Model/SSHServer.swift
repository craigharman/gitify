import Foundation

/// A saved SSH server connection used to browse and clone remote repositories.
struct SSHServer: Identifiable, Codable, Hashable {
    let id: UUID
    /// User-chosen display name (e.g. \u{201c}My VPS\u{201d}).
    var label: String
    /// Hostname or IP address.
    var host: String
    /// SSH username (typically \u{201c}git\u{201d} for hosting services).
    var user: String
    /// SSH port (default 22).
    var port: Int
    /// Base path on the server to scan for repositories.
    var basePath: String

    init(id: UUID = UUID(), label: String, host: String, user: String = "git",
         port: Int = 22, basePath: String = "~") {
        self.id = id
        self.label = label
        self.host = host
        self.user = user
        self.port = port
        self.basePath = basePath
    }
}

/// Persists the list of SSH servers to Application Support as JSON.
struct SSHServerStore {
    private let fileURL: URL

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gitify", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("ssh-servers.json")
    }

    func load() -> [SSHServer] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([SSHServer].self, from: data)) ?? []
    }

    func save(_ servers: [SSHServer]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(servers) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
