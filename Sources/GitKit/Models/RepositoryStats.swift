import Foundation

/// Line/file totals for one language in the repository.
public struct LanguageStat: Identifiable, Hashable, Sendable {
    public var id: String { language }
    public let language: String
    public let lines: Int
    public let files: Int

    public init(language: String, lines: Int, files: Int) {
        self.language = language
        self.lines = lines
        self.files = files
    }
}

/// A contributor and their commit count (`git shortlog`).
public struct Committer: Identifiable, Hashable, Sendable {
    public var id: String { email.isEmpty ? name : email }
    public let name: String
    public let email: String
    public let commits: Int

    public init(name: String, email: String, commits: Int) {
        self.name = name
        self.email = email
        self.commits = commits
    }
}
