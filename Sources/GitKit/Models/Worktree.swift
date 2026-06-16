import Foundation

/// A linked worktree (including the main one) as reported by `git worktree list --porcelain`.
public struct Worktree: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    /// HEAD commit SHA, or nil if the worktree is bare.
    public let head: String?
    /// Checked-out branch short name, or nil if detached/bare.
    public let branch: String?
    public let isBare: Bool
    public let isDetached: Bool
    /// True when the worktree is locked (`git worktree lock`).
    public let isLocked: Bool
    /// True for the repository's primary worktree.
    public let isMain: Bool

    public init(
        path: String,
        head: String?,
        branch: String?,
        isBare: Bool,
        isDetached: Bool,
        isLocked: Bool,
        isMain: Bool
    ) {
        self.path = path
        self.head = head
        self.branch = branch
        self.isBare = isBare
        self.isDetached = isDetached
        self.isLocked = isLocked
        self.isMain = isMain
    }
}
