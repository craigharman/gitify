import SwiftUI
import GitKit

/// Commit history with a lane-based graph (Screenshot 2): a graph gutter on the left,
/// commit rows, and a metadata inspector on the right.
struct HistoryView: View {
    let viewModel: RepositoryViewModel
    @State private var selection: Commit.ID?

    var body: some View {
        HSplitView {
            CommitGraphList(viewModel: viewModel, selection: $selection)
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            Group {
                if let selected = viewModel.commits.first(where: { $0.id == selection }) {
                    CommitInspector(commit: selected)
                } else {
                    ContentUnavailableView("No Commit Selected", systemImage: "sidebar.right")
                }
            }
            .frame(minWidth: 280, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Scrollable list of commit rows, each preceded by its slice of the graph.
private struct CommitGraphList: View {
    let viewModel: RepositoryViewModel
    @Binding var selection: Commit.ID?

    private let rowHeight: CGFloat = 46

    private var graphWidth: CGFloat {
        CGFloat(max(viewModel.graph.width, 1)) * GraphMetrics.laneWidth + 12
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.commits.enumerated()), id: \.element.id) { index, commit in
                    let node = index < viewModel.graph.nodes.count ? viewModel.graph.nodes[index] : nil
                    HStack(spacing: 0) {
                        GraphCell(node: node, rowHeight: rowHeight)
                            .frame(width: graphWidth, height: rowHeight)
                        CommitRowContent(commit: commit)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.trailing, 10)
                    }
                    .frame(height: rowHeight)
                    .background(selection == commit.id ? Color.accentColor.opacity(0.18) : .clear)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = commit.id }
                    .onAppear {
                        if index == viewModel.commits.count - 1, viewModel.canLoadMoreHistory {
                            Task { await viewModel.loadMoreHistory() }
                        }
                    }
                }
                if viewModel.isLoading {
                    ProgressView().controlSize(.small).padding(8)
                }
            }
        }
    }
}

/// Shared sizing for the graph gutter.
enum GraphMetrics {
    static let laneWidth: CGFloat = 16
    static let dotRadius: CGFloat = 4.5
    static let lineWidth: CGFloat = 1.6

    /// Distinct, stable colors per lane.
    static let palette: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .red, .indigo, .mint, .cyan,
    ]
    static func color(_ lane: Int) -> Color { palette[((lane % palette.count) + palette.count) % palette.count] }
    static func x(_ lane: Int) -> CGFloat { CGFloat(lane) * laneWidth + laneWidth / 2 }
}

/// Draws one row's portion of the graph: pass-through lines, edges into/out of the node,
/// and the commit dot. Edges connect across rows because lane columns are globally stable.
private struct GraphCell: View {
    let node: CommitNode?
    let rowHeight: CGFloat

    var body: some View {
        Canvas { context, size in
            guard let node else { return }
            let midY = size.height / 2
            let nodeX = GraphMetrics.x(node.lane)

            // Straight pass-through lines for unrelated branches.
            for lane in node.passThrough {
                let x = GraphMetrics.x(lane)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(GraphMetrics.color(lane)), lineWidth: GraphMetrics.lineWidth)
            }

            // Child edges coming down into the node (top half).
            for lane in node.incoming {
                context.stroke(curve(from: CGPoint(x: GraphMetrics.x(lane), y: 0),
                                     to: CGPoint(x: nodeX, y: midY)),
                               with: .color(GraphMetrics.color(lane)), lineWidth: GraphMetrics.lineWidth)
            }

            // Parent edges leaving the node (bottom half).
            for lane in node.outgoing {
                context.stroke(curve(from: CGPoint(x: nodeX, y: midY),
                                     to: CGPoint(x: GraphMetrics.x(lane), y: size.height)),
                               with: .color(GraphMetrics.color(lane)), lineWidth: GraphMetrics.lineWidth)
            }

            // The commit dot.
            let dot = CGRect(x: nodeX - GraphMetrics.dotRadius, y: midY - GraphMetrics.dotRadius,
                             width: GraphMetrics.dotRadius * 2, height: GraphMetrics.dotRadius * 2)
            context.fill(Circle().path(in: dot), with: .color(GraphMetrics.color(node.lane)))
            context.stroke(Circle().path(in: dot.insetBy(dx: -1, dy: -1)),
                           with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 1.5)
        }
    }

    /// A vertical line if the columns match, otherwise a smooth S-curve between them.
    private func curve(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        if abs(start.x - end.x) < 0.5 {
            path.addLine(to: end)
        } else {
            let midY = (start.y + end.y) / 2
            path.addCurve(to: end,
                          control1: CGPoint(x: start.x, y: midY),
                          control2: CGPoint(x: end.x, y: midY))
        }
        return path
    }
}

/// Text content of a commit row: avatar, ref pills, summary, and metadata.
private struct CommitRowContent: View {
    let commit: Commit

    var body: some View {
        HStack(spacing: 8) {
            AvatarView(name: commit.authorName)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    ForEach(commit.refs, id: \.self) { RefPill(text: $0) }
                    Text(commit.summary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(commit.authorName)
                    Text(commit.shortID).monospaced()
                    Text(commit.commitDate, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A small circular avatar with the author's initials and a stable per-name color.
struct AvatarView: View {
    let name: String

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
    private var hue: Double {
        Double(name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 360) / 360.0
    }

    var body: some View {
        Text(initials)
            .font(.caption2.bold())
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color(hue: hue, saturation: 0.5, brightness: 0.8)))
            .foregroundStyle(.white)
    }
}

struct RefPill: View {
    let text: String
    var body: some View {
        Text(text.replacingOccurrences(of: "HEAD -> ", with: ""))
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.25)))
            .foregroundStyle(color)
    }
    private var color: Color {
        if text.hasPrefix("tag:") { return .yellow }
        if text.hasPrefix("HEAD") { return .green }
        if text.contains("/") { return .purple }
        return .blue
    }
}

/// Right-hand inspector showing commit metadata (Screenshot 2 "Inspect Changes").
struct CommitInspector: View {
    let commit: Commit

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(commit.summary).font(.headline)
                if !commit.body.isEmpty {
                    Text(commit.body).font(.callout).foregroundStyle(.secondary)
                }
                Divider()
                field("Commit", commit.id)
                field("Author", "\(commit.authorName) <\(commit.authorEmail)>")
                field("Author Date", commit.authorDate.formatted(date: .abbreviated, time: .shortened))
                field("Committer", "\(commit.committerName) <\(commit.committerEmail)>")
                field("Commit Date", commit.commitDate.formatted(date: .abbreviated, time: .shortened))
                field("Parents", commit.parents.map { String($0.prefix(7)) }.joined(separator: ", "))
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.monospaced()).textSelection(.enabled)
        }
    }
}
