import SwiftUI
import GitKit

/// Side-by-side diff: old (left) and new (right) columns, with deletions/additions paired
/// across change blocks. Read-only (line staging stays in the unified view).
struct SplitDiffView: View {
    let diff: FileDiff
    let language: String

    /// One side-by-side row: a left (old) line and/or right (new) line.
    private struct Row: Identifiable {
        let id: Int
        let left: DiffLine?
        let right: DiffLine?
    }

    private var rows: [Row] {
        var result: [Row] = []
        var id = 0
        func emit(_ left: DiffLine?, _ right: DiffLine?) { result.append(Row(id: id, left: left, right: right)); id += 1 }

        for hunk in diff.hunks {
            emit(nil, nil) // hunk separator placeholder isn't needed; keep alignment simple
            result.removeLast()
            var dels: [DiffLine] = []
            var adds: [DiffLine] = []
            func flush() {
                for i in 0..<max(dels.count, adds.count) {
                    emit(i < dels.count ? dels[i] : nil, i < adds.count ? adds[i] : nil)
                }
                dels = []; adds = []
            }
            for line in hunk.lines {
                switch line.kind {
                case .context: flush(); emit(line, line)
                case .deletion: dels.append(line)
                case .addition: adds.append(line)
                }
            }
            flush()
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            // Vertical scroll only; each column is fixed at half the width and clips long
            // lines (switch to Unified to scroll long lines horizontally). A fixed-height
            // separator keeps rows from stretching.
            let column = max((geo.size.width - 1) / 2, 80)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        HStack(spacing: 0) {
                            side(row.left, isOld: true, width: column)
                            Rectangle().fill(.separator).frame(width: 1)
                            side(row.right, isOld: false, width: column)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
        }
    }

    private func side(_ line: DiffLine?, isOld: Bool, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(line.flatMap { isOld ? $0.oldLineNumber : $0.newLineNumber }.map(String.init) ?? "")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
                .padding(.trailing, 6)
            if let line {
                Text(SyntaxHighlighter.highlight(line.content.isEmpty ? " " : line.content, language: language))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 0.5)
        .frame(width: width, alignment: .leading)
        .background(background(line))
        .clipped()
    }

    private func background(_ line: DiffLine?) -> Color {
        switch line?.kind {
        case .addition: .green.opacity(0.14)
        case .deletion: .red.opacity(0.14)
        default: line == nil ? Color(nsColor: .quaternaryLabelColor).opacity(0.25) : .clear
        }
    }
}
