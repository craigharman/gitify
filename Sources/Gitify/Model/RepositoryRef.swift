import Foundation

/// A persisted reference to a repository the user has added to Gitify.
struct RepositoryRef: Identifiable, Codable, Hashable {
    let id: UUID
    /// Absolute path to the working-tree root.
    var path: String
    /// Display name (defaults to the directory name).
    var name: String

    init(id: UUID = UUID(), path: String, name: String? = nil) {
        self.id = id
        self.path = path
        self.name = name ?? URL(fileURLWithPath: path).lastPathComponent
    }

    var url: URL { URL(fileURLWithPath: path) }
}
