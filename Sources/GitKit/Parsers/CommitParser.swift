import Foundation

/// Parses the custom `git log --pretty=format` output produced by `CLIGitService.log`.
/// Records are separated by RS (0x1e); fields within a record by US (0x1f).
enum CommitParser {
    static func parse(_ output: String) -> [Commit] {
        // ISO8601DateFormatter isn't Sendable, so we keep one instance local to the call
        // (history loads a page at a time, so this is created infrequently).
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        return output.split(separator: "\u{1e}", omittingEmptySubsequences: true).compactMap { record in
            // git inserts a newline between records; drop any leading whitespace.
            let trimmed = record.drop(while: { $0 == "\n" || $0 == "\r" })
            let fields = trimmed.components(separatedBy: "\u{1f}")
            guard fields.count >= 11 else { return nil }

            let parents = fields[1].split(separator: " ").map(String.init)
            let refs = fields[10]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            return Commit(
                id: fields[0],
                parents: parents,
                authorName: fields[2],
                authorEmail: fields[3],
                authorDate: isoFormatter.date(from: fields[4]) ?? .distantPast,
                committerName: fields[5],
                committerEmail: fields[6],
                commitDate: isoFormatter.date(from: fields[7]) ?? .distantPast,
                summary: fields[8],
                body: fields[9].trimmingCharacters(in: .whitespacesAndNewlines),
                refs: refs
            )
        }
    }
}
