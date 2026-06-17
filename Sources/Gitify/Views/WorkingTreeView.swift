import SwiftUI
import GitKit

/// Identifies a selectable row: a file path on either the staged or unstaged side (a file
/// can appear on both when partially staged).
struct FileSelection: Hashable {
    let path: String
    let staged: Bool
}

/// Working-tree / staging view (Screenshot 3): staged + unstaged file lists with a diff
/// pane and a commit box.
struct WorkingTreeView: View {
    @Bindable var viewModel: RepositoryViewModel
    @State private var selection: FileSelection?

    var body: some View {
        if let status = viewModel.status {
            if status.hasChanges {
                HSplitView {
                    VStack(spacing: 0) {
                        fileList(status)
                        Divider()
                        CommitBox(viewModel: viewModel)
                    }
                    .frame(minWidth: 300, idealWidth: 360, maxHeight: .infinity)

                    diffPane
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // A List with native selection reliably drives file switching (plain
                // onTapGesture in a ScrollView dropped taps after the lists restructured).
                .onChange(of: selection) { _, sel in
                    guard let sel, let file = status.files.first(where: { $0.path == sel.path }) else { return }
                    Task { await viewModel.select(file, staged: sel.staged) }
                }
                .onChange(of: viewModel.selectedPath) { _, path in
                    // Keep the highlight in sync when selection is reset by a reload.
                    if path == nil { selection = nil }
                }
            } else {
                ContentUnavailableView("Clean Working Tree",
                                       systemImage: "checkmark.seal",
                                       description: Text("There are no changes to commit."))
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fileList(_ status: WorkingTreeStatus) -> some View {
        List(selection: $selection) {
            let staged = status.stagedFiles
            if !staged.isEmpty {
                Section {
                    ForEach(staged) { file in
                        StagingFileRow(file: file, staged: true, viewModel: viewModel)
                            .tag(FileSelection(path: file.path, staged: true))
                    }
                } header: {
                    sectionHeader("Staged", count: staged.count) {
                        Button("Unstage All") { Task { await unstageAll(staged) } }
                            .buttonStyle(.borderless).font(.caption)
                    }
                }
            }
            let unstaged = status.unstagedFiles
            if !unstaged.isEmpty {
                Section {
                    ForEach(unstaged) { file in
                        StagingFileRow(file: file, staged: false, viewModel: viewModel)
                            .tag(FileSelection(path: file.path, staged: false))
                    }
                } header: {
                    sectionHeader("Changes", count: unstaged.count) {
                        Button("Stage All") { Task { await viewModel.stageAll() } }
                            .buttonStyle(.borderless).font(.caption)
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private var diffPane: some View {
        if let diff = viewModel.currentDiff {
            DiffView(diff: diff,
                     actionLabel: viewModel.selectedStaged ? "Unstage Hunk" : "Stage Hunk",
                     onApplyHunk: { hunk in Task { await viewModel.applyHunk(hunk) } })
        } else {
            ContentUnavailableView("No File Selected", systemImage: "doc.text.magnifyingglass",
                                   description: Text("Select a file to view its changes."))
        }
    }

    private func sectionHeader(_ title: String, count: Int, @ViewBuilder action: () -> some View) -> some View {
        HStack {
            Text("\(title) (\(count))").font(.caption.bold()).foregroundStyle(.secondary)
            Spacer()
            action()
        }
    }

    private func unstageAll(_ files: [FileStatus]) async {
        for file in files { await viewModel.unstage(file) }
    }
}

/// A file row with a hover stage/unstage button and context menu. Selection/clicks are
/// handled by the enclosing `List`.
private struct StagingFileRow: View {
    let file: FileStatus
    let staged: Bool
    @Bindable var viewModel: RepositoryViewModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            StatusBadge(file: file)
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: file.path).lastPathComponent)
                Text(file.originalPath.map { "\($0) → \(file.path)" } ?? file.path)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if hovering {
                Button {
                    Task { staged ? await viewModel.unstage(file) : await viewModel.stage(file) }
                } label: {
                    Image(systemName: staged ? "minus.circle" : "plus.circle")
                }
                .buttonStyle(.borderless)
                .help(staged ? "Unstage" : "Stage")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            if file.isConflicted {
                Button("Take Ours (current branch)") { Task { await viewModel.resolveConflict(file, useOurs: true) } }
                Button("Take Theirs (incoming)") { Task { await viewModel.resolveConflict(file, useOurs: false) } }
                Button("Mark Resolved") { Task { await viewModel.markResolved(file) } }
            } else if staged {
                Button("Unstage") { Task { await viewModel.unstage(file) } }
            } else {
                Button("Stage") { Task { await viewModel.stage(file) } }
                Button("Discard Changes…", role: .destructive) { confirmDiscard() }
            }
        }
    }

    private func confirmDiscard() {
        let alert = NSAlert()
        alert.messageText = "Discard changes to \(URL(fileURLWithPath: file.path).lastPathComponent)?"
        alert.informativeText = "This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await viewModel.discard(file) }
        }
    }
}

/// Colored M/A/D/R/?? badge mirroring git's status letters.
struct StatusBadge: View {
    let file: FileStatus

    private var letter: String {
        if file.isConflicted { return "U" }
        if file.isUntracked { return "?" }
        let state = file.isStaged ? file.indexState : file.worktreeState
        return String(state.rawValue).uppercased()
    }

    private var color: Color {
        switch letter {
        case "A", "?": return .green
        case "M", "T": return .yellow
        case "D": return .red
        case "R", "C": return .blue
        case "U": return .orange
        default: return .secondary
        }
    }

    var body: some View {
        Text(letter)
            .font(.caption.monospaced().bold())
            .frame(width: 18, height: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.2)))
            .foregroundStyle(color)
    }
}

/// Commit message editor with Commit / Amend controls.
private struct CommitBox: View {
    @Bindable var viewModel: RepositoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $viewModel.commitMessage)
                .font(.body)
                .frame(height: 72)
                .overlay(alignment: .topLeading) {
                    if viewModel.commitMessage.isEmpty {
                        Text("Commit message")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5).padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            HStack {
                Toggle("Amend", isOn: Binding(
                    get: { viewModel.amendMode },
                    set: { on in
                        if on { Task { await viewModel.prepareAmend() } }
                        else { viewModel.amendMode = false }
                    }))
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                Button {
                    Task { await viewModel.commit() }
                } label: {
                    if viewModel.isCommitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(viewModel.amendMode ? "Amend Commit" : "Commit")
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!viewModel.canCommit)
            }
        }
        .padding(10)
    }
}
