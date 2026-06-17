import Foundation

/// Merges `git show --name-status -z` (status + rename info) with `--numstat -z`
/// (added/deleted line counts) into a single list of `FileChange`s.
enum CommitChangesParser {
    static func parse(nameStatus: String, numstat: String) -> [FileChange] {
        let counts = parseNumstat(numstat)
        var changes: [FileChange] = []

        let tokens = nameStatus.components(separatedBy: "\u{0}")
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            if token.isEmpty { i += 1; continue }
            guard let statusChar = token.first,
                  let status = FileChange.Status(rawValue: String(statusChar)) else { i += 1; continue }

            let path: String
            let oldPath: String?
            if (status == .renamed || status == .copied), i + 2 < tokens.count {
                oldPath = tokens[i + 1]
                path = tokens[i + 2]
                i += 3
            } else if i + 1 < tokens.count {
                oldPath = nil
                path = tokens[i + 1]
                i += 2
            } else {
                break
            }

            let count = counts[path] ?? (0, 0, false)
            changes.append(FileChange(path: path, oldPath: oldPath, status: status,
                                      additions: count.0, deletions: count.1, isBinary: count.2))
        }
        return changes
    }

    /// Returns path → (additions, deletions, isBinary). Renames carry an empty path field
    /// followed by old/new path tokens.
    private static func parseNumstat(_ numstat: String) -> [String: (Int, Int, Bool)] {
        var result: [String: (Int, Int, Bool)] = [:]
        let tokens = numstat.components(separatedBy: "\u{0}")
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            if token.isEmpty { i += 1; continue }
            let fields = token.components(separatedBy: "\t")
            guard fields.count >= 3 else { i += 1; continue }
            let isBinary = fields[0] == "-"
            let adds = Int(fields[0]) ?? 0
            let dels = Int(fields[1]) ?? 0

            var path = fields[2]
            if path.isEmpty, i + 2 < tokens.count {
                // Rename: real path is the second following token (new path).
                path = tokens[i + 2]
                i += 3
            } else {
                i += 1
            }
            result[path] = (adds, dels, isBinary)
        }
        return result
    }
}
