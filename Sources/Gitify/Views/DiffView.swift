import SwiftUI
import GitKit

/// Renders a `FileDiff` as a unified diff with line numbers and add/remove coloring.
/// When `onApplyHunk` is provided, each hunk header gets a stage/unstage button.
struct DiffView: View {
    let diff: FileDiff
    var actionLabel: String = "Stage Hunk"
    var onApplyHunk: ((DiffHunk) -> Void)? = nil

    var body: some View {
        if diff.isBinary {
            ContentUnavailableView("Binary File", systemImage: "doc.badge.gearshape",
                                   description: Text("Binary content can't be displayed."))
        } else if diff.hunks.isEmpty {
            ContentUnavailableView("No Changes", systemImage: "doc.plaintext",
                                   description: Text("This file has no textual changes."))
        } else {
            // Anchor the content to at least the column width so row backgrounds span the
            // full pane (and only longer lines trigger horizontal scrolling). Without this
            // the diff width tracks the longest line and changes per file.
            GeometryReader { geo in
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(diff.hunks) { hunk in
                            hunkHeader(hunk)
                            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                                DiffLineRow(line: line)
                            }
                        }
                    }
                    // Fill at least the viewport so short diffs pin to the top-leading
                    // corner instead of centering, and long lines still scroll.
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                }
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            }
        }
    }

    private func hunkHeader(_ hunk: DiffHunk) -> some View {
        HStack(spacing: 8) {
            Text(hunk.header)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let onApplyHunk, !diff.isNew {
                Button(actionLabel) { onApplyHunk(hunk) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
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
