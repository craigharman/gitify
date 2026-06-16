import Foundation

/// Parses `git status --porcelain=v2 --branch -z` output.
///
/// Records are NUL-terminated. Rename/copy (type `2`) entries are special: the original
/// path is carried in the *following* NUL-delimited token, so the iterator consumes two.
enum StatusParser {
    static func parse(_ data: Data) -> WorkingTreeStatus {
        let text = String(decoding: data, as: UTF8.self)
        let tokens = text.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)

        var branch: String?
        var upstream: String?
        var ahead = 0
        var behind = 0
        var isDetached = false
        var files: [FileStatus] = []

        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            guard let first = token.first else { i += 1; continue }

            switch first {
            case "#":
                parseHeader(token, branch: &branch, upstream: &upstream,
                            ahead: &ahead, behind: &behind, isDetached: &isDetached)
            case "1":
                if let file = parseOrdinary(token) { files.append(file) }
            case "2":
                // Rename/copy: original path is the next token.
                let original = (i + 1 < tokens.count) ? tokens[i + 1] : nil
                if let file = parseRename(token, originalPath: original) { files.append(file) }
                i += 1 // consume the original-path token
            case "u":
                if let file = parseUnmerged(token) { files.append(file) }
            case "?":
                let path = String(token.dropFirst(2))
                files.append(FileStatus(path: path, originalPath: nil,
                                        indexState: .untracked, worktreeState: .untracked,
                                        isConflicted: false))
            case "!":
                break // ignored entries are not surfaced
            default:
                break
            }
            i += 1
        }

        return WorkingTreeStatus(branch: branch, upstream: upstream, ahead: ahead,
                                 behind: behind, isDetached: isDetached, files: files)
    }

    private static func parseHeader(
        _ token: String,
        branch: inout String?, upstream: inout String?,
        ahead: inout Int, behind: inout Int, isDetached: inout Bool
    ) {
        // e.g. "# branch.head main", "# branch.ab +1 -2", "# branch.upstream origin/main"
        let parts = token.split(separator: " ")
        guard parts.count >= 3 else { return }
        switch parts[1] {
        case "branch.head":
            let value = parts[2...].joined(separator: " ")
            if value == "(detached)" { isDetached = true } else { branch = value }
        case "branch.upstream":
            upstream = parts[2...].joined(separator: " ")
        case "branch.ab":
            // "+A" "-B"
            for field in parts[2...] {
                if field.hasPrefix("+") { ahead = Int(field.dropFirst()) ?? 0 }
                else if field.hasPrefix("-") { behind = Int(field.dropFirst()) ?? 0 }
            }
        default:
            break
        }
    }

    /// `1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>`
    private static func parseOrdinary(_ token: String) -> FileStatus? {
        let parts = token.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
        guard parts.count == 9, parts[1].count == 2 else { return nil }
        let (x, y) = xy(parts[1])
        return FileStatus(path: String(parts[8]), originalPath: nil,
                          indexState: x, worktreeState: y, isConflicted: false)
    }

    /// `2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <Xscore> <path>`
    private static func parseRename(_ token: String, originalPath: String?) -> FileStatus? {
        let parts = token.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
        guard parts.count == 10, parts[1].count == 2 else { return nil }
        let (x, y) = xy(parts[1])
        return FileStatus(path: String(parts[9]), originalPath: originalPath,
                          indexState: x, worktreeState: y, isConflicted: false)
    }

    /// `u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>`
    private static func parseUnmerged(_ token: String) -> FileStatus? {
        let parts = token.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
        guard parts.count == 11, parts[1].count == 2 else { return nil }
        let (x, y) = xy(parts[1])
        return FileStatus(path: String(parts[10]), originalPath: nil,
                          indexState: x, worktreeState: y, isConflicted: true)
    }

    private static func xy(_ field: Substring) -> (FileStatus.State, FileStatus.State) {
        let chars = Array(field)
        let x = FileStatus.State(rawValue: chars[0]) ?? .unmodified
        let y = FileStatus.State(rawValue: chars[1]) ?? .unmodified
        return (x, y)
    }
}
