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
    /// The exact raw text of this hunk (its `@@` line through its last line), used to
    /// build a patch for hunk-level staging.
    public let rawText: String

    public init(id: Int, header: String, oldStart: Int, oldCount: Int,
                newStart: Int, newCount: Int, lines: [DiffLine], rawText: String = "") {
        self.id = id
        self.header = header
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
        self.rawText = rawText
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
    /// The raw header lines (`diff --git`, `index`, `---`, `+++`) preceding the first hunk,
    /// used to assemble a valid patch for hunk-level staging.
    public let header: String

    public var isEmpty: Bool { hunks.isEmpty && !isBinary }
    public var addedLines: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .addition }.count } }
    public var removedLines: Int { hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .deletion }.count } }

    public init(path: String, oldPath: String?, isBinary: Bool, isNew: Bool,
                isDeleted: Bool, hunks: [DiffHunk], header: String = "") {
        self.path = path
        self.oldPath = oldPath
        self.isBinary = isBinary
        self.isNew = isNew
        self.isDeleted = isDeleted
        self.hunks = hunks
        self.header = header
    }

    /// Whether the file has a recognised image extension.
    public var isImage: Bool {
        Self.imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "tiff", "tif", "bmp", "svg", "ico", "heic", "heif",
    ]

    public static func empty(path: String) -> FileDiff {
        FileDiff(path: path, oldPath: nil, isBinary: false, isNew: false, isDeleted: false, hunks: [])
    }
}

/// The old and new image data for a binary image diff.
public struct ImageDiffData: Sendable {
    public let oldImage: Data?
    public let newImage: Data?

    public init(oldImage: Data?, newImage: Data?) {
        self.oldImage = oldImage
        self.newImage = newImage
    }
}
