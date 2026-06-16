import Foundation

/// Parses unified diff output (`git diff --no-color -U<n>`) for a single file.
enum DiffParser {
    static func parse(_ text: String, fallbackPath: String) -> FileDiff {
        var path = fallbackPath
        var oldPath: String?
        var isBinary = false
        var isNew = false
        var isDeleted = false
        var hunks: [DiffHunk] = []

        // State for the hunk currently being accumulated.
        var hunkLines: [DiffLine] = []
        var hunkHeader: String?
        var hOldStart = 0, hOldCount = 0, hNewStart = 0, hNewCount = 0
        var oldNo = 0, newNo = 0

        func flushHunk() {
            guard let header = hunkHeader else { return }
            hunks.append(DiffHunk(id: hunks.count, header: header,
                                  oldStart: hOldStart, oldCount: hOldCount,
                                  newStart: hNewStart, newCount: hNewCount,
                                  lines: hunkLines))
            hunkLines = []
            hunkHeader = nil
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if rawLine.hasPrefix("diff --git") {
                continue
            } else if rawLine.hasPrefix("new file") {
                isNew = true
            } else if rawLine.hasPrefix("deleted file") {
                isDeleted = true
            } else if rawLine.hasPrefix("Binary files") || rawLine.hasPrefix("GIT binary patch") {
                isBinary = true
            } else if rawLine.hasPrefix("rename from ") {
                oldPath = String(rawLine.dropFirst("rename from ".count))
            } else if rawLine.hasPrefix("--- ") {
                let p = String(rawLine.dropFirst(4))
                if p != "/dev/null" { oldPath = stripPrefix(p) }
            } else if rawLine.hasPrefix("+++ ") {
                let p = String(rawLine.dropFirst(4))
                if p != "/dev/null" { path = stripPrefix(p) }
            } else if rawLine.hasPrefix("@@") {
                flushHunk()
                let parsed = parseHunkHeader(rawLine)
                hOldStart = parsed.oldStart; hOldCount = parsed.oldCount
                hNewStart = parsed.newStart; hNewCount = parsed.newCount
                oldNo = parsed.oldStart; newNo = parsed.newStart
                hunkHeader = rawLine
            } else if hunkHeader != nil {
                // Inside a hunk: classify by the leading marker.
                guard let marker = rawLine.first else {
                    // Blank line inside a hunk represents an empty context line.
                    hunkLines.append(DiffLine(kind: .context, content: "",
                                              oldLineNumber: oldNo, newLineNumber: newNo))
                    oldNo += 1; newNo += 1
                    continue
                }
                let content = String(rawLine.dropFirst())
                switch marker {
                case "+":
                    hunkLines.append(DiffLine(kind: .addition, content: content,
                                              oldLineNumber: nil, newLineNumber: newNo))
                    newNo += 1
                case "-":
                    hunkLines.append(DiffLine(kind: .deletion, content: content,
                                              oldLineNumber: oldNo, newLineNumber: nil))
                    oldNo += 1
                case " ":
                    hunkLines.append(DiffLine(kind: .context, content: content,
                                              oldLineNumber: oldNo, newLineNumber: newNo))
                    oldNo += 1; newNo += 1
                case "\\":
                    break // "\ No newline at end of file"
                default:
                    break
                }
            }
        }
        flushHunk()

        return FileDiff(path: path, oldPath: oldPath, isBinary: isBinary,
                        isNew: isNew, isDeleted: isDeleted, hunks: hunks)
    }

    /// Strips the `a/` or `b/` prefix git adds to diff paths.
    private static func stripPrefix(_ path: String) -> String {
        if path.hasPrefix("a/") || path.hasPrefix("b/") { return String(path.dropFirst(2)) }
        return path
    }

    /// Parses `@@ -oldStart,oldCount +newStart,newCount @@` (counts default to 1).
    private static func parseHunkHeader(_ line: String) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int) {
        // Extract the segment between the two "@@" markers.
        let parts = line.components(separatedBy: "@@")
        guard parts.count >= 2 else { return (0, 0, 0, 0) }
        let ranges = parts[1].trimmingCharacters(in: .whitespaces).split(separator: " ")
        var oldStart = 0, oldCount = 1, newStart = 0, newCount = 1
        for range in ranges {
            let sign = range.first
            let numbers = range.dropFirst().split(separator: ",")
            let start = Int(numbers.first ?? "0") ?? 0
            let count = numbers.count > 1 ? (Int(numbers[1]) ?? 1) : 1
            if sign == "-" { oldStart = start; oldCount = count }
            else if sign == "+" { newStart = start; newCount = count }
        }
        return (oldStart, oldCount, newStart, newCount)
    }
}
