import Foundation

/// A persisted reference to a repository the user has added to Gitify.
struct RepositoryRef: Identifiable, Codable, Hashable {
    let id: UUID
    /// Absolute path to the working-tree root (local or remote).
    var path: String
    /// Display name (defaults to the directory name).
    var name: String

    // SSH connection details \u{2014} nil for local repos.
    var sshHost: String?
    var sshUser: String?
    var sshPort: Int?

    /// Whether this repository is accessed over SSH rather than the local filesystem.
    var isRemote: Bool { sshHost != nil }

    init(id: UUID = UUID(), path: String, name: String? = nil,
         sshHost: String? = nil, sshUser: String? = nil, sshPort: Int? = nil) {
        self.id = id
        self.path = path
        self.name = name ?? URL(fileURLWithPath: path).lastPathComponent
        self.sshHost = sshHost
        self.sshUser = sshUser
        self.sshPort = sshPort
    }

    var url: URL { URL(fileURLWithPath: path) }
}
