import Foundation

/// A git submodule, from `git submodule status`.
public struct Submodule: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let sha: String
    /// The described ref the submodule is at (e.g. `heads/main`), if any.
    public let ref: String?
    /// `-` prefix: not yet initialized/checked out.
    public let isInitialized: Bool
    /// `+` prefix: the checked-out commit differs from the recorded one.
    public let isModified: Bool
    /// `U` prefix: merge conflicts.
    public let hasConflicts: Bool

    public init(path: String, sha: String, ref: String?,
                isInitialized: Bool, isModified: Bool, hasConflicts: Bool) {
        self.path = path
        self.sha = sha
        self.ref = ref
        self.isInitialized = isInitialized
        self.isModified = isModified
        self.hasConflicts = hasConflicts
    }
}
