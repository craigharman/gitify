import Foundation

/// A single release entry parsed from CHANGELOG.md.
struct ReleaseEntry: Identifiable, Sendable {
    let version: String
    let date: String
    let sections: [Section]

    var id: String { version }

    struct Section: Sendable {
        let heading: String
        let items: [String]
    }
}

/// Parses a keep-a-changelog style CHANGELOG.md into structured release entries.
enum ChangelogParser {

    /// Parse the full changelog text and return releases in document order (newest first).
    static func parse(_ text: String) -> [ReleaseEntry] {
        let lines = text.components(separatedBy: "\n")
        var entries: [ReleaseEntry] = []

        var currentVersion: String?
        var currentDate: String?
        var currentSections: [ReleaseEntry.Section] = []
        var currentHeading: String?
        var currentItems: [String] = []

        for line in lines {
            // Release header: ## [1.12.0](url) (2026-06-30)
            if line.hasPrefix("## [") {
                // Flush previous entry
                if let version = currentVersion, let date = currentDate {
                    if let heading = currentHeading, !currentItems.isEmpty {
                        currentSections.append(.init(heading: heading, items: currentItems))
                    }
                    entries.append(.init(version: version, date: date, sections: currentSections))
                }

                // Parse new header
                let stripped = line.dropFirst(4) // remove "## ["
                if let closeBracket = stripped.firstIndex(of: "]") {
                    currentVersion = String(stripped[stripped.startIndex..<closeBracket])
                } else {
                    currentVersion = nil
                }
                // Date is in the last parentheses
                if let lastOpen = line.lastIndex(of: "("),
                   let lastClose = line.lastIndex(of: ")"),
                   lastOpen < lastClose {
                    let dateStart = line.index(after: lastOpen)
                    currentDate = String(line[dateStart..<lastClose])
                } else {
                    currentDate = nil
                }
                currentSections = []
                currentHeading = nil
                currentItems = []
                continue
            }

            // Section header: ### Features, ### Bug Fixes
            if line.hasPrefix("### ") {
                if let heading = currentHeading, !currentItems.isEmpty {
                    currentSections.append(.init(heading: heading, items: currentItems))
                }
                currentHeading = String(line.dropFirst(4))
                currentItems = []
                continue
            }

            // Bullet item: * description ([#30](url)) ([hash](url))
            if line.hasPrefix("* ") {
                let cleaned = cleanItem(String(line.dropFirst(2)))
                if !cleaned.isEmpty {
                    currentItems.append(cleaned)
                }
            }
        }

        // Flush final entry
        if let version = currentVersion, let date = currentDate {
            if let heading = currentHeading, !currentItems.isEmpty {
                currentSections.append(.init(heading: heading, items: currentItems))
            }
            entries.append(.init(version: version, date: date, sections: currentSections))
        }

        return entries
    }

    /// Strip markdown link references like ([#30](url)) and ([hash](url)) from an item.
    private static func cleanItem(_ text: String) -> String {
        // Remove patterns like ([#30](url)) and ([hash](url))
        var result = text
        // Pattern: ([ ... ]( ... ))  — parenthesised markdown links
        while let openParen = result.range(of: " \\(\\[[^\\]]*\\]\\([^)]*\\)\\)", options: .regularExpression) {
            result.removeSubrange(openParen)
        }
        result = result.trimmingCharacters(in: .whitespaces)
        // Capitalize first letter for display.
        guard let first = result.first else { return result }
        return first.uppercased() + result.dropFirst()
    }
}
