import SwiftUI
import GitKit

/// Working-tree / staging view (Screenshot 3): staged + unstaged file lists with a diff
/// pane and a commit box.
struct WorkingTreeView: View {
    @Bindable var viewModel: RepositoryViewModel

    var body: some View {
        if let status = viewModel.status {
            if status.hasChanges {
                HSplitView {
                    VStack(spacing: 0) {
                        fileLists(status)
                        Divider()
                        CommitBox(viewModel: viewModel)
                    }
                    .frame(minWidth: 300, idealWidth: 360, maxHeight: .infinity)

                    diffPane
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Clean Working Tree",
                                       systemImage: "checkmark.seal",
                                       description: Text("There are no changes to commit."))
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func fileLists(_ status: WorkingTreeStatus) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let staged = status.stagedFiles
                if !staged.isEmpty {
                    sectionHeader("Staged", count: staged.count) {
                        Button("Unstage All") { Task { await unstageAll(staged) } }
                            .buttonStyle(.borderless).font(.caption)
                    }
                    ForEach(staged) { file in
                        StagingFileRow(file: file, staged: true, viewModel: viewModel)
                    }
                }
                let unstaged = status.unstagedFiles
                if !unstaged.isEmpty {
                    sectionHeader("Changes", count: unstaged.count) {
                        Button("Stage All") { Task { await viewModel.stageAll() } }
                            .buttonStyle(.borderless).font(.caption)
                    }
                    ForEach(unstaged) { file in
                        StagingFileRow(file: file, staged: false, viewModel: viewModel)
                    }
                }
            }
        }
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
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 2)
    }

    private func unstageAll(_ files: [FileStatus]) async {
        for file in files { await viewModel.unstage(file) }
    }
}

/// A selectable file row with a hover stage/unstage button.
private struct StagingFileRow: View {
    let file: FileStatus
    let staged: Bool
    @Bindable var viewModel: RepositoryViewModel
    @State private var hovering = false

    private var isSelected: Bool {
        viewModel.selectedPath == file.path && viewModel.selectedStaged == staged
    }

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
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { Task { await viewModel.select(file, staged: staged) } }
        .onHover { hovering = $0 }
        .contextMenu {
            if staged {
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
