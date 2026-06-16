import SwiftUI
import GitKit

/// Renders a `FileDiff` as a unified diff with line numbers and add/remove coloring.
struct DiffView: View {
    let diff: FileDiff

    var body: some View {
        if diff.isBinary {
            ContentUnavailableView("Binary File", systemImage: "doc.badge.gearshape",
                                   description: Text("Binary content can't be displayed."))
        } else if diff.hunks.isEmpty {
            ContentUnavailableView("No Changes", systemImage: "doc.plaintext",
                                   description: Text("This file has no textual changes."))
        } else {
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(diff.hunks) { hunk in
                        hunkHeader(hunk.header)
                        ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                            DiffLineRow(line: line)
                        }
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
        }
    }

    private func hunkHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08))
    }
}

private struct DiffLineRow: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            gutter(line.oldLineNumber)
            gutter(line.newLineNumber)
            Text(marker)
                .frame(width: 14)
                .foregroundStyle(.secondary)
            Text(line.content.isEmpty ? " " : line.content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 0.5)
        .background(background)
    }

    private var marker: String {
        switch line.kind {
        case .addition: return "+"
        case .deletion: return "-"
        case .context: return " "
        }
    }

    private var background: Color {
        switch line.kind {
        case .addition: return .green.opacity(0.14)
        case .deletion: return .red.opacity(0.14)
        case .context: return .clear
        }
    }

    private func gutter(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: 40, alignment: .trailing)
            .padding(.trailing, 4)
    }
}
