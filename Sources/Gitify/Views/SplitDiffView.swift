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
            ScrollView([.vertical, .horizontal]) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        HStack(spacing: 0) {
                            side(row.left, isOld: true, width: geo.size.width / 2)
                            Divider()
                            side(row.right, isOld: false, width: geo.size.width / 2)
                        }
                    }
                }
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
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
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 6)
            if let line {
                Text(SyntaxHighlighter.highlight(line.content.isEmpty ? " " : line.content, language: language))
                    .fixedSize(horizontal: true, vertical: false)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 0.5)
        .frame(width: max(width, 120), alignment: .leading)
        .background(background(line))
    }

    private func background(_ line: DiffLine?) -> Color {
        switch line?.kind {
        case .addition: .green.opacity(0.14)
        case .deletion: .red.opacity(0.14)
        default: line == nil ? Color(nsColor: .quaternaryLabelColor).opacity(0.25) : .clear
        }
    }
}
