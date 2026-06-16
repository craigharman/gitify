import Foundation

/// A configured remote (`git remote`).
public struct GitRemote: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let fetchURL: String
    public let pushURL: String

    public init(name: String, fetchURL: String, pushURL: String) {
        self.name = name
        self.fetchURL = fetchURL
        self.pushURL = pushURL
    }
}

/// An entry from `git reflog`.
public struct ReflogEntry: Identifiable, Hashable, Sendable {
    public var id: String { selector }
    /// e.g. `HEAD@{0}`.
    public let selector: String
    public let sha: String
    /// The reflog action, e.g. `commit`, `checkout`, `merge`.
    public let action: String
    /// The descriptive message.
    public let message: String
    public let date: Date

    public init(selector: String, sha: String, action: String, message: String, date: Date) {
        self.selector = selector
        self.sha = sha
        self.action = action
        self.message = message
        self.date = date
    }
}
