import Foundation

/// Parses `git reflog --format='%gd<US>%H<US>%gs<US>%cI'`, e.g.
/// `HEAD@{0}<US>1a2b...<US>commit: add feature<US>2026-01-01T10:00:00+00:00`.
enum ReflogParser {
    static func parse(_ output: String) -> [ReflogEntry] {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        return output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let fields = line.components(separatedBy: "\u{1f}")
            guard fields.count >= 4 else { return nil }
            // The subject is "<action>: <message>" (action has no colon when there's no message).
            let subject = fields[2]
            let action: String
            let message: String
            if let colon = subject.firstIndex(of: ":") {
                action = String(subject[..<colon])
                message = String(subject[subject.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            } else {
                action = subject
                message = ""
            }
            return ReflogEntry(
                selector: fields[0],
                sha: fields[1],
                action: action,
                message: message,
                date: isoFormatter.date(from: fields[3]) ?? .distantPast
            )
        }
    }
}
