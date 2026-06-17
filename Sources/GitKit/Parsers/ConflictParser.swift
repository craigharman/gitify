import Foundation

/// A region of a conflicted file.
public enum ConflictSegment: Hashable, Sendable {
    /// Non-conflicting text (already agreed).
    case text(String)
    /// A conflict with our side, their side, and (diff3 only) the common base.
    case conflict(ours: String, theirs: String, base: String?)
}

/// Splits a file containing git conflict markers into resolvable segments.
public enum ConflictParser {
    public static func parse(_ contents: String) -> [ConflictSegment] {
        let lines = contents.components(separatedBy: "\n")
        var segments: [ConflictSegment] = []
        var text: [String] = []

        func flushText() {
            if !text.isEmpty { segments.append(.text(text.joined(separator: "\n"))); text = [] }
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("<<<<<<<") {
                flushText()
                var ours: [String] = [], base: [String] = [], theirs: [String] = []
                var section = 0 // 0 = ours, 1 = base (diff3), 2 = theirs
                i += 1
                while i < lines.count, !lines[i].hasPrefix(">>>>>>>") {
                    let l = lines[i]
                    if l.hasPrefix("|||||||") { section = 1 }
                    else if l.hasPrefix("=======") { section = 2 }
                    else {
                        switch section {
                        case 0: ours.append(l)
                        case 1: base.append(l)
                        default: theirs.append(l)
                        }
                    }
                    i += 1
                }
                i += 1 // skip the >>>>>>> line
                segments.append(.conflict(ours: ours.joined(separator: "\n"),
                                          theirs: theirs.joined(separator: "\n"),
                                          base: base.isEmpty ? nil : base.joined(separator: "\n")))
            } else {
                text.append(line)
                i += 1
            }
        }
        flushText()
        return segments
    }
}
