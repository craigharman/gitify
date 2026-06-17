import Foundation

/// The result of a dry-run merge (`git merge-tree`), used to warn about conflicts before
/// performing a real merge.
public struct MergePreview: Sendable {
    /// Paths that would conflict. Empty means the merge is clean.
    public let conflictingFiles: [String]

    public var conflictCount: Int { conflictingFiles.count }
    public var isClean: Bool { conflictingFiles.isEmpty }

    public init(conflictingFiles: [String]) {
        self.conflictingFiles = conflictingFiles
    }
}

/// An in-progress, interrupted git operation (e.g. a conflicted merge or rebase).
public enum RepositoryOperation: String, Sendable {
    case merge
    case rebase
}

/// How `git reset` treats the index and working tree.
public enum ResetMode: String, Sendable {
    case soft   // move HEAD only
    case mixed  // move HEAD + reset index (default)
    case hard   // move HEAD + reset index + working tree (destructive)
}
