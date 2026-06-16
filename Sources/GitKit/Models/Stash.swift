import Foundation

/// An entry from `git stash list`.
public struct Stash: Identifiable, Hashable, Sendable {
    /// Stash ref, e.g. `stash@{0}`.
    public let id: String
    /// Zero-based index within the stash stack.
    public let index: Int
    /// Branch the stash was created on, when recoverable from the message.
    public let branch: String?
    /// Human-readable message.
    public let message: String

    public init(id: String, index: Int, branch: String?, message: String) {
        self.id = id
        self.index = index
        self.branch = branch
        self.message = message
    }
}
