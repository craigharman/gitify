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
            // Each row is a single, non-wrapping line whose width is at least the viewport,
            // so backgrounds span the full pane, long lines scroll horizontally, and (with
            // uniform row heights) the lazy stack lays out without gaps.
            GeometryReader { geo in
                ScrollView([.vertical, .horizontal]) {
                    // A plain VStack (not Lazy) renders every row, so multi-hunk diffs lay
                    // out without the blank gaps lazy height-estimation produced.
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(diff.hunks) { hunk in
                            hunkHeader(hunk, width: geo.size.width)
                            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                                DiffLineRow(line: line, width: geo.size.width)
                            }
                        }
                    }
                    // Top-align short diffs instead of centering them.
                    .frame(minHeight: geo.size.height, alignment: .topLeading)
                }
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            }
        }
    }

    private func hunkHeader(_ hunk: DiffHunk, width: CGFloat) -> some View {
        Text(hunk.header)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .frame(minWidth: width, alignment: .leading)
            .background(Color.accentColor.opacity(0.08))
            // The stage/unstage action is pinned to the viewport's trailing edge.
            .overlay(alignment: .trailing) {
                if let onApplyHunk, !diff.isNew {
                    Button(actionLabel) { onApplyHunk(hunk) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .padding(.trailing, 10)
                }
            }
    }
}

private struct DiffLineRow: View {
    let line: DiffLine
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            gutter(line.oldLineNumber)
            gutter(line.newLineNumber)
            Text(marker)
                .frame(width: 14)
                .foregroundStyle(.secondary)
            Text(line.content.isEmpty ? " " : line.content)
                .fixedSize(horizontal: true, vertical: false) // never wrap; scroll instead
        }
        .padding(.vertical, 0.5)
        .frame(minWidth: width, alignment: .leading)
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
