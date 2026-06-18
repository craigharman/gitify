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
            GeometryReader { _ in
                if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    changeList
                }
            }
            .frame(maxWidth: .infinity, minHeight: 140)

            CommitFileDiffPane(fileDiff: fileDiff)
                .frame(maxWidth: .infinity, minHeight: 120)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: ref) { await load() }
        .onChange(of: selectedFile) { _, path in
            guard let path else { fileDiff = nil; return }
            Task { fileDiff = await viewModel.commitFileDiff(ref, path: path) }
        }
    }

    /// The changed-files list. Built from a ScrollView/LazyVStack (rather than `List`) so the
    /// rows reliably span the full pane width regardless of the diff pane's content.
    private var changeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("\(changes.count) Changed File\(changes.count == 1 ? "" : "s")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                ForEach(changes) { change in
                    ChangeRow(change: change)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedFile == change.path ? Color.accentColor.opacity(0.18) : .clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { selectedFile = change.path }
                        .padding(.horizontal, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// The diff side of the changeset split: the selected file's diff, or a placeholder.
/// Concrete (not an inline if/else) so selecting a changed file doesn't reset the dragged divider.
private struct CommitFileDiffPane: View {
    let fileDiff: FileDiff?

    var body: some View {
        // GeometryReader so the pane keeps a constant (greedy) size whether the diff or the
        // placeholder is shown — otherwise VSplitView shifts the divider on file selection.
        GeometryReader { _ in
            if let fileDiff {
                DiffView(diff: fileDiff)
            } else {
                ContentUnavailableView("No File Selected", systemImage: "doc.text.magnifyingglass",
                                       description: Text("Select a changed file to view its diff."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
