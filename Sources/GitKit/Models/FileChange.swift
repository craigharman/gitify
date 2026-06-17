import Foundation

/// A single file changed by a commit, for the history "Inspect Changes" panel.
public struct FileChange: Identifiable, Hashable, Sendable {
    public enum Status: String, Sendable {
        case added = "A"
        case modified = "M"
        case deleted = "D"
        case renamed = "R"
        case copied = "C"
        case typeChanged = "T"
    }

    public var id: String { path }
    public let path: String
    public let oldPath: String?
    public let status: Status
    public let additions: Int
    public let deletions: Int
    /// Binary files report `-`/`-` from numstat rather than line counts.
    public let isBinary: Bool

    public init(path: String, oldPath: String?, status: Status,
                additions: Int, deletions: Int, isBinary: Bool) {
        self.path = path
        self.oldPath = oldPath
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.isBinary = isBinary
    }
}
