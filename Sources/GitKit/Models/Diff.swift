import Foundation

/// A single line within a diff hunk.
public struct DiffLine: Hashable, Sendable {
    public enum Kind: Sendable {
        case context
        case addition
        case deletion
    }

    public let kind: Kind
    /// Line content without the leading `+`/`-`/space marker.
    public let content: String
    /// Line number in the old file (nil for additions).
    public let oldLineNumber: Int?
    /// Line number in the new file (nil for deletions).
    public let newLineNumber: Int?

    public init(kind: Kind, content: String, oldLineNumber: Int?, newLineNumber: Int?) {
        self.kind = kind
        self.content = content
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
    }
}

/// A contiguous block of changes (`@@ ... @@`).
public struct DiffHunk: Identifiable, Hashable, Sendable {
    public let id: Int
    /// The raw `@@ -a,b +c,d @@ section` header line.
    public let header: String
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let lines: [DiffLine]

    public init(id: Int, header: String, oldStart: Int, oldCount: Int,
                newStart: Int, newCount: Int, lines: [DiffLine]) {
        self.id = id
        self.header = header
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
    }
}

/// The diff for a single file.
public struct FileDiff: Sendable {
    public let path: String
    public let oldPath: String?
    public let isBinary: Bool
    public let isNew: Bool
    public let isDeleted: Bool
    public let hunks: [DiffHunk]

    public var isEmpty: Bool { hunks.isEmpty && !isBinary }
    public var addedLines: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .addition }.count } }
    public var removedLines: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .deletion }.count } }

    public init(path: String, oldPath: String?, isBinary: Bool, isNew: Bool,
                isDeleted: Bool, hunks: [DiffHunk]) {
        self.path = path
        self.oldPath = oldPath
        self.isBinary = isBinary
        self.isNew = isNew
        self.isDeleted = isDeleted
        self.hunks = hunks
    }

    public static func empty(path: String) -> FileDiff {
        FileDiff(path: path, oldPath: nil, isBinary: false, isNew: false, isDeleted: false, hunks: [])
    }
}
