import SwiftUI
import GitKit

/// Identifies a selectable row: a file path on either the staged or unstaged side (a file
/// can appear on both when partially staged).
struct FileSelection: Hashable {
    let path: String
    let staged: Bool
}

/// Identifies a file to open in the conflict editor (Identifiable for `.sheet(item:)`).
private struct ConflictTarget: Identifiable {
    let id = UUID()
    let path: String
}

/// Working-tree / staging view (Screenshot 3): staged + unstaged file lists with a diff
/// pane and a commit box.
struct WorkingTreeView: View {
    @Bindable var viewModel: RepositoryViewModel
    /// The set of currently selected files (supports multi-select via cmd/shift-click).
    @State private var selection: Set<FileSelection> = []
    /// The last file that was clicked (anchor for shift-click range selection).
    @State private var lastClicked: FileSelection?
    @State private var search = ""
    @State private var conflictTarget: ConflictTarget?

    private func matches(_ file: FileStatus) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || file.path.lowercased().contains(q)
    }

    var body: some View {
        if let status = viewModel.status {
            if status.hasChanges {
                HSplitView {
                    VStack(spacing: 0) {
                        SearchField(text: $search, prompt: "Filter files")
                        fileList(status)
                        Divider()
                        CommitBox(viewModel: viewModel)
                    }
                    .frame(minWidth: 300, idealWidth: 360, maxHeight: .infinity)

                    DiffPane(viewModel: viewModel)
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: viewModel.selectedPath) { _, path in
                    if path == nil {
                        selection = []
                        lastClicked = nil
                    }
                    // Prune selection for files that no longer exist after a mutation.
                    let paths = Set((viewModel.status?.files ?? []).map(\.path))
                    selection = selection.filter { paths.contains($0.path) }
                }
                .sheet(item: $conflictTarget) { target in
                    ConflictEditorView(viewModel: viewModel, path: target.path)
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

    // MARK: - Row click handling

    /// Handles a click on a file row, applying cmd/shift modifier logic.
    fileprivate func handleRowClick(
        _ clicked: FileSelection,
        file: FileStatus,
        orderedSelections: [FileSelection],
        modifiers: NSEvent.ModifierFlags
    ) {
        if modifiers.contains(.command) {
            // Cmd-click: toggle this file in the selection.
            if selection.contains(clicked) {
                selection.remove(clicked)
            } else {
                selection.insert(clicked)
            }
            lastClicked = clicked
            // Load diff for the clicked file.
            Task { await viewModel.select(file, staged: clicked.staged) }
        } else if modifiers.contains(.shift), let anchor = lastClicked {
            // Shift-click: select range from last-clicked to this file.
            if let startIdx = orderedSelections.firstIndex(of: anchor),
               let endIdx = orderedSelections.firstIndex(of: clicked) {
                let range = min(startIdx, endIdx)...max(startIdx, endIdx)
                let rangeSelections = Set(orderedSelections[range])
                selection.formUnion(rangeSelections)
            } else {
                selection.insert(clicked)
            }
            lastClicked = clicked
            Task { await viewModel.select(file, staged: clicked.staged) }
        } else {
            // Plain click: single-select.
            selection = [clicked]
            lastClicked = clicked
            Task { await viewModel.select(file, staged: clicked.staged) }
        }
    }

    // MARK: - Selected-file helpers

    /// Returns the selected unstaged files resolved against the current status.
    private func selectedUnstagedFiles(in status: WorkingTreeStatus) -> [FileStatus] {
        let paths = Set(selection.filter { !$0.staged }.map(\.path))
        guard !paths.isEmpty else { return [] }
        return status.unstagedFiles.filter { paths.contains($0.path) }
    }

    /// Returns the selected staged files resolved against the current status.
    private func selectedStagedFiles(in status: WorkingTreeStatus) -> [FileStatus] {
        let paths = Set(selection.filter { $0.staged }.map(\.path))
        guard !paths.isEmpty else { return [] }
        return status.stagedFiles.filter { paths.contains($0.path) }
    }

    // MARK: - File list

    private func fileList(_ status: WorkingTreeStatus) -> some View {
        // Build a flat ordered list of FileSelection entries for shift-click range computation.
        let stagedFiles = status.stagedFiles.filter(matches)
        let unstagedFiles = status.unstagedFiles.filter(matches)
        let orderedSelections: [FileSelection] =
            stagedFiles.map { FileSelection(path: $0.path, staged: true) } +
            unstagedFiles.map { FileSelection(path: $0.path, staged: false) }

        // Resolve selected peers per side for multi-select context menus.
        let stagedPeers = selectedStagedFiles(in: status)
        let unstagedPeers = selectedUnstagedFiles(in: status)

        return List {
            if !stagedFiles.isEmpty {
                Section {
                    ForEach(stagedFiles) { file in
                        StagingFileRow(file: file, staged: true, viewModel: viewModel,
                                       isSelected: selection.contains(FileSelection(path: file.path, staged: true)),
                                       peers: stagedPeers,
                                       onResolveConflict: { conflictTarget = ConflictTarget(path: $0) },
                                       onClick: { mods in
                                           handleRowClick(FileSelection(path: file.path, staged: true),
                                                          file: file, orderedSelections: orderedSelections, modifiers: mods)
                                       })
                    }
                } header: {
                    sectionHeader("Staged", count: stagedFiles.count) {
                        Button("Unstage All") { Task { await viewModel.unstageFiles(stagedFiles) } }
                            .buttonStyle(.borderless).font(.caption)
                    }
                }
            }
            if !unstagedFiles.isEmpty {
                Section {
                    ForEach(unstagedFiles) { file in
                        StagingFileRow(file: file, staged: false, viewModel: viewModel,
                                       isSelected: selection.contains(FileSelection(path: file.path, staged: false)),
                                       peers: unstagedPeers,
                                       onResolveConflict: { conflictTarget = ConflictTarget(path: $0) },
                                       onClick: { mods in
                                           handleRowClick(FileSelection(path: file.path, staged: false),
                                                          file: file, orderedSelections: orderedSelections, modifiers: mods)
                                       })
                    }
                } header: {
                    sectionHeader("Changes", count: unstagedFiles.count) {
                        Button("Stage All") { Task { await viewModel.stageAll() } }
                            .buttonStyle(.borderless).font(.caption)
                    }
                }
            }
        }
        .listStyle(.inset)
        .environment(\.defaultMinListRowHeight, 0) // let rows size naturally
    }

    private func sectionHeader(_ title: String, count: Int, @ViewBuilder action: () -> some View) -> some View {
        HStack {
            Text("\(title) (\(count))").font(.caption.bold()).foregroundStyle(.secondary)
            Spacer()
            action()
        }
    }

}

/// The diff side of the working-tree split: the selected file's diff, or a placeholder.
/// A concrete view so the conditional doesn't change the split child's identity (which would
/// reset the user's dragged divider on every selection).
private struct DiffPane: View {
    let viewModel: RepositoryViewModel

    var body: some View {
        // Wrapped in a GeometryReader so the pane reports the same (greedy, flexible) size whether
        // the diff or the placeholder is shown — otherwise HSplitView redistributes width on the
        // first selection (DiffView is itself a GeometryReader; the bare placeholder is not).
        GeometryReader { _ in
            if let diff = viewModel.currentDiff {
                DiffView(diff: diff,
                         actionLabel: viewModel.selectedStaged ? "Unstage Hunk" : "Stage Hunk",
                         lineActionLabel: viewModel.selectedStaged ? "Unstage Lines" : "Stage Lines",
                         onApplyHunk: { hunk in Task { await viewModel.applyHunk(hunk) } },
                         onApplyLines: { hunk, lines in Task { await viewModel.applyLines(hunk, lines) } })
            } else {
                ContentUnavailableView("No File Selected", systemImage: "doc.text.magnifyingglass",
                                       description: Text("Select a file to view its changes."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Reads the current keyboard modifier flags at the moment of a gesture.
@MainActor private func currentModifiers() -> NSEvent.ModifierFlags {
    NSApp.currentEvent?.modifierFlags.intersection([.command, .shift]) ?? []
}

/// A file row with a hover stage/unstage button and context menu. Clicking the row selects
/// it; cmd-click adds/removes from the selection; shift-click selects a range.
private struct StagingFileRow: View {
    let file: FileStatus
    let staged: Bool
    @Bindable var viewModel: RepositoryViewModel
    let isSelected: Bool
    /// The resolved peer files on the same side when multi-selected, or just this file.
    var peers: [FileStatus] = []
    var onResolveConflict: ((String) -> Void)? = nil
    var onClick: ((NSEvent.ModifierFlags) -> Void)? = nil
    @State private var hovering = false

    /// The files the context menu should act on: the multi-select peers if this row is part
    /// of a multi-selection, otherwise just this single file.
    private var targets: [FileStatus] {
        peers.count > 1 ? peers : [file]
    }

    private var isMulti: Bool { targets.count > 1 }
    private var allUntracked: Bool { targets.allSatisfy(\.isUntracked) }
    private var allTracked: Bool { targets.allSatisfy { !$0.isUntracked } }

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
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onClick?(currentModifiers()) }
        .contextMenu {
            // File actions — always available.
            Button(isMulti ? "Show \(targets.count) in Finder" : "Show in Finder") {
                viewModel.revealInFinder(targets)
            }
            if !isMulti {
                Button("Open in Terminal") { viewModel.openInTerminal(file) }
            }
            Button(isMulti ? "Open \(targets.count) in Editor" : "Open in Editor") {
                viewModel.openInDefaultEditor(targets)
            }

            Divider()

            // Conflict resolution — single conflicted file only.
            if file.isConflicted && !isMulti {
                Button("Resolve in Editor…") { onResolveConflict?(file.path) }
                Divider()
                Button("Take Ours (current branch)") { Task { await viewModel.resolveConflict(file, useOurs: true) } }
                Button("Take Theirs (incoming)") { Task { await viewModel.resolveConflict(file, useOurs: false) } }
                Button("Mark Resolved") { Task { await viewModel.markResolved(file) } }
            } else if staged {
                // Staged files.
                Button(isMulti ? "Unstage \(targets.count) Files" : "Unstage") {
                    Task { await viewModel.unstageFiles(targets) }
                }
            } else {
                // Unstaged files.
                Button(isMulti ? "Stage \(targets.count) Files" : "Stage") {
                    Task { await viewModel.stageFiles(targets) }
                }

                // Discard — only for tracked files with modifications.
                if allTracked {
                    Button(isMulti ? "Discard \(targets.count) Changes…" : "Discard Changes…",
                           role: .destructive) { confirmDiscard(targets) }
                }

                // Delete — for untracked files.
                if allUntracked {
                    Button(isMulti ? "Delete \(targets.count) Files…" : "Delete File…",
                           role: .destructive) { confirmDelete(targets) }
                }

                Divider()

                // Ignore — untracked files only.
                if allUntracked {
                    Button(isMulti ? "Ignore \(targets.count) Files" : "Ignore") {
                        Task { await viewModel.ignoreFiles(targets) }
                    }
                }

                // Untrack — tracked files only.
                if allTracked {
                    Button(isMulti ? "Untrack \(targets.count) Files" : "Untrack") {
                        Task { await viewModel.untrackFiles(targets) }
                    }
                }
            }
        }
    }

    private func confirmDiscard(_ files: [FileStatus]) {
        let alert = NSAlert()
        alert.messageText = files.count == 1
            ? "Discard changes to \(URL(fileURLWithPath: files[0].path).lastPathComponent)?"
            : "Discard changes to \(files.count) files?"
        alert.informativeText = "This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await viewModel.discardFiles(files) }
        }
    }

    private func confirmDelete(_ files: [FileStatus]) {
        let alert = NSAlert()
        alert.messageText = files.count == 1
            ? "Delete \(URL(fileURLWithPath: files[0].path).lastPathComponent)?"
            : "Delete \(files.count) files?"
        alert.informativeText = "The files will be moved to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await viewModel.deleteFiles(files) }
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

/// A split button: primary action on the left, chevron dropdown on the right, drawn as a
/// single cohesive pill using the accent color so both halves always match.
private struct SplitCommitButton: View {
    @Bindable var viewModel: RepositoryViewModel
    @Binding var commitAndPush: Bool
    let primaryLabel: String
    let onSetMode: (Bool) -> Void

    @State private var hovering = false

    private var disabled: Bool { !viewModel.canCommit }

    var body: some View {
        HStack(spacing: 0) {
            // Primary action
            Button {
                Task {
                    await viewModel.commit()
                    if commitAndPush && viewModel.loadError == nil {
                        await viewModel.push()
                    }
                }
            } label: {
                Group {
                    if viewModel.isCommitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(primaryLabel)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [.command])

            // Thin separator
            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(width: 1)
                .padding(.vertical, 4)

            // Dropdown mode picker
            Menu {
                Button {
                    onSetMode(false)
                } label: {
                    if !commitAndPush { Label("Commit", systemImage: "checkmark") }
                    else { Text("Commit") }
                }
                .tint(nil)
                Button {
                    onSetMode(true)
                } label: {
                    if commitAndPush { Label("Commit & Push", systemImage: "checkmark") }
                    else { Text("Commit & Push") }
                }
                .tint(nil)
            } label: {
                Text("")
            }
            .menuStyle(.borderlessButton)
            .tint(.white)
            .fixedSize()
            .padding(.trailing, 4)
        }
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 5).fill(disabled ? Color.accentColor.opacity(0.5) : Color.accentColor))
        .fixedSize()
        .disabled(disabled)
    }
}

/// Commit message editor with Commit / Amend controls.
private struct CommitBox: View {
    @Bindable var viewModel: RepositoryViewModel
    @FocusState private var editorFocused: Bool
    @State private var commitAndPush: Bool

    init(viewModel: RepositoryViewModel) {
        self.viewModel = viewModel
        let key = SidebarDefaults.commitAndPushKey(viewModel.ref.path)
        _commitAndPush = State(initialValue: UserDefaults.standard.bool(forKey: key))
    }

    private var primaryLabel: String {
        if viewModel.amendMode {
            return commitAndPush ? "Amend & Push" : "Amend Commit"
        }
        return commitAndPush ? "Commit & Push" : "Commit"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                // Placeholder shares the editor's text-start position and clears as soon as
                // the field is focused (not only when typing begins).
                if viewModel.commitMessage.isEmpty && !editorFocused {
                    Text("Commit message")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $viewModel.commitMessage)
                    .focused($editorFocused)
                    .font(.body)
                    .scrollContentBackground(.hidden)
            }
            .padding(8) // inner padding so text/cursor isn't against the border
            .frame(height: 88)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
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
                SplitCommitButton(viewModel: viewModel, commitAndPush: $commitAndPush,
                                  primaryLabel: primaryLabel, onSetMode: setCommitAndPush)
            }
        }
        .padding(10)
    }

    private func setCommitAndPush(_ value: Bool) {
        commitAndPush = value
        let key = SidebarDefaults.commitAndPushKey(viewModel.ref.path)
        UserDefaults.standard.set(value, forKey: key)
    }
}
