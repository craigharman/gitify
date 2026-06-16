import Foundation

/// A single commit as surfaced in the history/graph view.
public struct Commit: Identifiable, Hashable, Sendable {
    /// Full 40-char SHA.
    public let id: String
    public let parents: [String]
    public let authorName: String
    public let authorEmail: String
    public let authorDate: Date
    public let committerName: String
    public let committerEmail: String
    public let commitDate: Date
    /// First line of the commit message.
    public let summary: String
    /// Full commit message (subject + body).
    public let body: String
    /// Ref names decorating this commit (branches, tags, HEAD), as reported by git.
    public let refs: [String]

    public var shortID: String { String(id.prefix(7)) }
    public var isMerge: Bool { parents.count > 1 }

    public init(
        id: String,
        parents: [String],
        authorName: String,
        authorEmail: String,
        authorDate: Date,
        committerName: String,
        committerEmail: String,
        commitDate: Date,
        summary: String,
        body: String,
        refs: [String]
    ) {
        self.id = id
        self.parents = parents
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.authorDate = authorDate
        self.committerName = committerName
        self.committerEmail = committerEmail
        self.commitDate = commitDate
        self.summary = summary
        self.body = body
        self.refs = refs
    }
}
