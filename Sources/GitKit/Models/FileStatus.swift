import Foundation

/// The git status of a single path in the working tree, derived from
/// `git status --porcelain=v2`.
public struct FileStatus: Identifiable, Hashable, Sendable {
    /// Two-letter XY status code where X is the staged (index) state and Y is the
    /// unstaged (working-tree) state, mirroring porcelain output.
    public enum State: Character, Sendable {
        case unmodified = "."
        case modified = "M"
        case added = "A"
        case deleted = "D"
        case renamed = "R"
        case copied = "C"
        case typeChanged = "T"
        case updatedButUnmerged = "U"
        case untracked = "?"
        case ignored = "!"
    }

    public var id: String { path }
    public let path: String
    /// Original path for renames/copies.
    public let originalPath: String?
    /// Index (staged) state.
    public let indexState: State
    /// Working-tree (unstaged) state.
    public let worktreeState: State
    /// True when the entry is in a merge conflict (unmerged).
    public let isConflicted: Bool

    public var isStaged: Bool { indexState != .unmodified && indexState != .untracked }
    public var hasUnstagedChanges: Bool { worktreeState != .unmodified }
    public var isUntracked: Bool { indexState == .untracked || worktreeState == .untracked }

    public init(
        path: String,
        originalPath: String?,
        indexState: State,
        worktreeState: State,
        isConflicted: Bool
    ) {
        self.path = path
        self.originalPath = originalPath
        self.indexState = indexState
        self.worktreeState = worktreeState
        self.isConflicted = isConflicted
    }
}

/// A snapshot of the working tree: branch context plus changed files.
public struct WorkingTreeStatus: Sendable {
    public let branch: String?
    public let upstream: String?
    public let ahead: Int
    public let behind: Int
    public let isDetached: Bool
    public let files: [FileStatus]

    public var stagedFiles: [FileStatus] { files.filter(\.isStaged) }
    public var unstagedFiles: [FileStatus] { files.filter { $0.hasUnstagedChanges || $0.isUntracked } }
    public var hasChanges: Bool { !files.isEmpty }

    public init(
        branch: String?,
        upstream: String?,
        ahead: Int,
        behind: Int,
        isDetached: Bool,
        files: [FileStatus]
    ) {
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.isDetached = isDetached
        self.files = files
    }
}
