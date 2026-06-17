import SwiftUI
import GitKit

/// The history "Inspect Changes" panel: commit metadata plus the changeset (files +
/// per-file diff) for the commit.
struct CommitDetailView: View {
    let commit: Commit
    let viewModel: RepositoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            metadata
            Divider()
            ChangesetDiffPane(ref: commit.id, viewModel: viewModel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(commit.summary).font(.headline)
            if !commit.body.isEmpty {
                Text(commit.body).font(.callout).foregroundStyle(.secondary).lineLimit(4)
            }
            HStack(spacing: 8) {
                AvatarView(name: commit.authorName)
                VStack(alignment: .leading, spacing: 1) {
                    Text(commit.authorName).font(.callout)
                    Text("\(commit.shortID) · \(commit.commitDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(commit.id, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help("Copy full SHA")
            }
        }
        .padding(12)
    }
}

/// A reusable changeset panel for any ref (a commit SHA or a stash selector): the list of
/// changed files with +/- counts on top, and the selected file's diff below.
struct ChangesetDiffPane: View {
    let ref: String
    let viewModel: RepositoryViewModel

    @State private var changes: [FileChange] = []
    @State private var selectedFile: String?
    @State private var fileDiff: FileDiff?
    @State private var loading = false

    var body: some View {
        VSplitView {
            Group {
                if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedFile) {
                        Section("\(changes.count) Changed File\(changes.count == 1 ? "" : "s")") {
                            ForEach(changes) { change in
                                ChangeRow(change: change).tag(change.path)
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minHeight: 140)

            Group {
                if let fileDiff {
                    DiffView(diff: fileDiff)
                } else {
                    ContentUnavailableView("No File Selected", systemImage: "doc.text.magnifyingglass",
                                           description: Text("Select a changed file to view its diff."))
                }
            }
            .frame(minHeight: 120)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: ref) { await load() }
        .onChange(of: selectedFile) { _, path in
            guard let path else { fileDiff = nil; return }
            Task { fileDiff = await viewModel.commitFileDiff(ref, path: path) }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        selectedFile = nil
        fileDiff = nil
        changes = await viewModel.commitChanges(ref)
        if let first = changes.first { selectedFile = first.path }
    }
}

/// Right-click actions for a commit in the history list.
struct CommitContextMenu: View {
    let commit: Commit
    let viewModel: RepositoryViewModel

    var body: some View {
        Button("Checkout Commit") { Task { await viewModel.checkout(commit.id) } }
        Button("Create Branch Here…") {
            if let name = Prompt.text(title: "New Branch",
                                      message: "Create from \(commit.shortID).", confirm: "Create") {
                Task { await viewModel.createBranch(name: name, checkout: true) }
            }
        }
        Button("Create Tag Here…") {
            if let name = Prompt.text(title: "New Tag", message: "Tag \(commit.shortID).", confirm: "Create") {
                Task { await viewModel.createTag(name: name, on: commit.id, message: nil) }
            }
        }
        Divider()
        Button("Cherry-pick") { Task { await viewModel.cherryPick(commit.id) } }
        Button("Revert") { Task { await viewModel.revert(commit.id) } }
        Menu("Reset “\(viewModel.currentBranch?.name ?? "HEAD")” to Here") {
            Button("Soft — keep changes staged") { confirmReset(.soft) }
            Button("Mixed — keep changes unstaged") { confirmReset(.mixed) }
            Button("Hard — discard changes", role: .destructive) { confirmReset(.hard) }
        }
        Divider()
        Button("Copy SHA") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.id, forType: .string)
        }
    }

    private func confirmReset(_ mode: ResetMode) {
        let warn = mode == .hard
        if !warn || Prompt.confirmDestructive(
            title: "Hard reset to \(commit.shortID)?",
            message: "This permanently discards working-tree and staged changes after this commit.",
            confirm: "Reset") {
            Task { await viewModel.reset(to: commit.id, mode: mode) }
        }
    }
}

/// A changed-file row: status badge, path, and +/- counts.
private struct ChangeRow: View {
    let change: FileChange

    var body: some View {
        HStack(spacing: 8) {
            badge
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: change.path).lastPathComponent)
                Text(change.oldPath.map { "\($0) → \(change.path)" } ?? change.path)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if change.isBinary {
                Text("bin").font(.caption2).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    if change.additions > 0 { Text("+\(change.additions)").foregroundStyle(.green) }
                    if change.deletions > 0 { Text("−\(change.deletions)").foregroundStyle(.red) }
                }
                .font(.caption.monospacedDigit())
            }
        }
        .padding(.vertical, 2)
    }

    private var badge: some View {
        Text(change.status.rawValue)
            .font(.caption.monospaced().bold())
            .frame(width: 18, height: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.2)))
            .foregroundStyle(color)
    }

    private var color: Color {
        switch change.status {
        case .added: .green
        case .modified, .typeChanged: .yellow
        case .deleted: .red
        case .renamed, .copied: .blue
        }
    }
}
