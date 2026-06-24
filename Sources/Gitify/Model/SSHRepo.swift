import Foundation

/// A repository discovered on a remote SSH server.
struct SSHRepo: Identifiable, Hashable {
    var id: String { path }
    /// Absolute path on the server (e.g. \u{201c}/srv/git/project.git\u{201d}).
    let path: String
    /// Display name derived from the path (directory name without .git suffix).
    let name: String
    /// Full SSH clone URL (e.g. \u{201c}ssh://git@host:22/srv/git/project.git\u{201d}).
    let cloneURL: String
}
