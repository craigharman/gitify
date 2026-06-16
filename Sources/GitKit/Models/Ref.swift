import Foundation

/// A git reference: a local/remote branch or a tag.
public struct Ref: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case localBranch
        case remoteBranch
        case tag
    }

    /// Full ref name, e.g. `refs/heads/main`, `refs/remotes/origin/main`, `refs/tags/v1.0`.
    public let id: String
    public let kind: Kind
    /// Short display name, e.g. `main`, `origin/main`, `v1.0`.
    public let name: String
    /// SHA the ref points at (peeled, for annotated tags).
    public let targetSHA: String
    /// Whether this is the currently checked-out branch (HEAD).
    public let isHead: Bool
    /// For local branches: the configured upstream short name, if any.
    public let upstream: String?
    /// For local branches with an upstream: commits ahead / behind.
    public let ahead: Int?
    public let behind: Int?

    public init(
        id: String,
        kind: Kind,
        name: String,
        targetSHA: String,
        isHead: Bool = false,
        upstream: String? = nil,
        ahead: Int? = nil,
        behind: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.targetSHA = targetSHA
        self.isHead = isHead
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
    }
}
