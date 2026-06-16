import SwiftUI
import GitKit

/// Commit history list (Screenshot 2). A full lane-based graph canvas is planned for M3;
/// this presents the topologically-ordered commit list with ref decorations.
struct HistoryView: View {
    let viewModel: RepositoryViewModel
    @State private var selection: Commit.ID?

    var body: some View {
        HSplitView {
            commitList
                .frame(minWidth: 360)
            if let selected = viewModel.commits.first(where: { $0.id == selection }) {
                CommitInspector(commit: selected)
                    .frame(minWidth: 280)
            } else {
                ContentUnavailableView("No Commit Selected", systemImage: "sidebar.right")
                    .frame(minWidth: 280)
            }
        }
    }

    private var commitList: some View {
        List(selection: $selection) {
            ForEach(viewModel.commits) { commit in
                CommitRow(commit: commit).tag(commit.id)
            }
            if viewModel.canLoadMoreHistory {
                Button("Load More…") {
                    Task { await viewModel.loadMoreHistory() }
                }
                .buttonStyle(.borderless)
            }
        }
        .listStyle(.inset)
    }
}

struct CommitRow: View {
    let commit: Commit

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(name: commit.authorName)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    ForEach(commit.refs, id: \.self) { ref in
                        RefPill(text: ref)
                    }
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
            Spacer()
        }
        .padding(.vertical, 3)
    }
}

/// A small circular avatar with the author's initials.
struct AvatarView: View {
    let name: String

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.caption2.bold())
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color(hue: hue, saturation: 0.5, brightness: 0.8)))
            .foregroundStyle(.white)
    }

    /// Stable hue derived from the name so each author keeps a consistent color.
    private var hue: Double {
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(sum % 360) / 360.0
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
