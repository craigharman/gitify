import Foundation

/// Parses `git stash list --format='%gd<US>%gs'` output, e.g.
/// `stash@{0}<US>WIP on main: 1a2b3c4 Some message`.
enum StashParser {
    static func parse(_ output: String) -> [Stash] {
        output.split(separator: "\n", omittingEmptySubsequences: true).enumerated().compactMap { index, line in
            let fields = line.components(separatedBy: "\u{1f}")
            guard fields.count >= 2 else { return nil }
            let selector = fields[0]
            let subject = fields[1]
            return Stash(
                id: selector,
                index: index,
                branch: branchName(from: subject),
                message: subject
            )
        }
    }

    /// Subjects look like `WIP on <branch>: <sha> <msg>` or `On <branch>: <msg>`.
    private static func branchName(from subject: String) -> String? {
        let prefixes = ["WIP on ", "On "]
        for prefix in prefixes where subject.hasPrefix(prefix) {
            let rest = subject.dropFirst(prefix.count)
            if let colon = rest.firstIndex(of: ":") {
                return String(rest[..<colon])
            }
        }
        return nil
    }
}
