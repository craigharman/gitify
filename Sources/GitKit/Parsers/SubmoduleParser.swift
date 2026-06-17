import Foundation

/// Parses `git submodule status` lines: `<flag><sha> <path> (<ref>)`, where `flag` is a
/// space (in sync), `-` (uninitialized), `+` (differs), or `U` (conflicts).
enum SubmoduleParser {
    static func parse(_ output: String) -> [Submodule] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { rawLine in
            let line = String(rawLine)
            guard let flag = line.first else { return nil }
            let rest = String(line.dropFirst())
            let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count >= 2 else { return nil }
            let sha = String(parts[0])

            var remainder = String(parts[1])
            var ref: String?
            if let open = remainder.lastIndex(of: "("), remainder.hasSuffix(")") {
                ref = String(remainder[remainder.index(after: open)..<remainder.index(before: remainder.endIndex)])
                remainder = String(remainder[..<open]).trimmingCharacters(in: .whitespaces)
            }

            return Submodule(
                path: remainder,
                sha: sha,
                ref: ref,
                isInitialized: flag != "-",
                isModified: flag == "+",
                hasConflicts: flag == "U"
            )
        }
    }
}
