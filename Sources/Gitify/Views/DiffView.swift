import SwiftUI
import AppKit
import GitKit

/// Keeps diff text layout bounded. A single minified or generated line can be hundreds of
/// KB, and laying that out as one CoreText line blocks the main thread for seconds.
enum DiffText {
    static let maxColumns = 1_000
    static let tabWidth = 4

    /// `content` with tabs expanded to spaces and capped at `maxColumns`, ending in an
    /// ellipsis when cut.
    static func display(_ content: String) -> String {
        if content.isEmpty { return " " }
        if content.utf8.count <= maxColumns, !content.contains("\t") { return content }
        var out = ""
        var column = 0
        for ch in content {
            if column >= maxColumns { out += " \u{2026}"; break }
            if ch == "\t" {
                let n = tabWidth - column % tabWidth
                out += String(repeating: " ", count: n)
                column += n
            } else {
                out.append(ch)
                column += 1
            }
        }
        return out
    }

    /// Estimated width of `text` in monospaced columns (wide characters count double).
    static func columns(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + ($1.value >= 0x1100 ? 2 : 1) }
    }

    /// Advance of one column in the body-size monospaced font.
    static let columnWidth: CGFloat = {
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize,
                                               weight: .regular)
        return ceil(("0" as NSString).size(withAttributes: [.font: font]).width)
    }()
}

/// Identifies a selectable diff line: its hunk id and index within that hunk.
private struct LineRef: Hashable { let hunk: Int; let index: Int }

/// Renders a `FileDiff` as a unified diff with line numbers and add/remove coloring.
/// When `onApplyHunk` is provided, each hunk header gets a stage/unstage button; when
/// `onApplyLines` is provided, individual added/removed lines can be selected and staged.
struct DiffView: View {
    let diff: FileDiff
    var imageDiffData: ImageDiffData? = nil
    var actionLabel: String = "Stage Hunk"
    var lineActionLabel: String = "Stage Lines"
    var onApplyHunk: ((DiffHunk) -> Void)? = nil
    var onApplyLines: ((DiffHunk, Set<Int>) -> Void)? = nil

    @State private var selected: Set<LineRef> = []
    @State private var mode: DiffMode = .unified

    private enum DiffMode: String, CaseIterable { case unified = "Unified", split = "Split" }
    private var language: String { (diff.path as NSString).pathExtension.lowercased() }

    var body: some View {
        if diff.isBinary, let imageDiffData {
            ImageDiffView(data: imageDiffData, isNew: diff.isNew, isDeleted: diff.isDeleted)
        } else if diff.isBinary {
            ContentUnavailableView("Binary File", systemImage: "doc.badge.gearshape",
                                   description: Text("Binary content can\u{2019}t be displayed."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if diff.hunks.isEmpty {
            ContentUnavailableView("No Changes", systemImage: "doc.plaintext",
                                   description: Text("This file has no textual changes."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                header
                if mode == .unified {
                    diffBody
                } else {
                    SplitDiffView(diff: diff, language: language)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("", selection: $mode) {
                ForEach(DiffMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            if onApplyLines != nil, !selected.isEmpty, mode == .unified {
                Text("\(selected.count) selected").font(.caption).foregroundStyle(.secondary)
                Button("Clear") { selected = [] }.buttonStyle(.borderless).font(.caption)
                Button(lineActionLabel) { applySelected() }.controlSize(.small)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.bar)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(.separator), alignment: .bottom)
    }

    private var diffBody: some View {
        // Each row is a single, non-wrapping line whose width is at least the viewport,
        // so backgrounds span the full pane and long lines scroll horizontally. The stack
        // gets an explicit width up front; otherwise, inside a horizontal ScrollView, the
        // LazyVStack must lay out every row's text just to learn how wide it is.
        GeometryReader { geo in
            let rowWidth = max(geo.size.width, contentWidth)
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(diff.hunks) { hunk in
                        hunkHeader(hunk, width: geo.size.width)
                        ForEach(Array(hunk.lines.enumerated()), id: \.offset) { index, line in
                            let ref = LineRef(hunk: hunk.id, index: index)
                            DiffLineRow(
                                line: line, width: rowWidth, language: language,
                                selectable: onApplyLines != nil && !diff.isNew && line.kind != .context,
                                isSelected: selected.contains(ref),
                                onToggle: { toggle(ref) })
                        }
                    }
                }
                .frame(width: rowWidth, alignment: .leading)
                .frame(minHeight: geo.size.height, alignment: .topLeading)
            }
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
        }
    }

    /// Width of the widest row, estimated from column counts (the font is monospaced).
    private var contentWidth: CGFloat {
        var widest = 0
        for hunk in diff.hunks {
            widest = max(widest, DiffText.columns(hunk.header))
            for line in hunk.lines { widest = max(widest, DiffText.columns(DiffText.display(line.content))) }
        }
        // Selection toggle (16) + two gutters (44 each) + marker (14) + slack.
        return 16 + 88 + 14 + 8 + CGFloat(widest) * DiffText.columnWidth
    }

    private func toggle(_ ref: LineRef) {
        if selected.contains(ref) { selected.remove(ref) } else { selected.insert(ref) }
    }

    private func applySelected() {
        guard let onApplyLines else { return }
        // Group selected lines by hunk, then apply each hunk's selection.
        let byHunk = Dictionary(grouping: selected, by: \.hunk)
        for (hunkId, refs) in byHunk {
            guard let hunk = diff.hunks.first(where: { $0.id == hunkId }) else { continue }
            onApplyLines(hunk, Set(refs.map(\.index)))
        }
        selected = []
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
    var language: String = ""
    var selectable: Bool = false
    var isSelected: Bool = false
    var onToggle: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            if selectable {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.caption2)
                    .frame(width: 16)
            }
            gutter(line.oldLineNumber)
            gutter(line.newLineNumber)
            Text(marker)
                .frame(width: 14)
                .foregroundStyle(.secondary)
            Text(SyntaxHighlighter.highlight(DiffText.display(line.content), language: language))
                .fixedSize(horizontal: true, vertical: false) // never wrap; scroll instead
        }
        .padding(.vertical, 0.5)
        .frame(minWidth: width, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.22) : background)
        .contentShape(Rectangle())
        .onTapGesture { if selectable { onToggle?() } }
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
        case .addition: return .green.opacity(0.22)
        case .deletion: return .red.opacity(0.22)
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
