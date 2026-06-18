import SwiftUI
import GitKit

/// Sections available within a repository, mirroring the left rail in the mockups.
/// Codable so the current selection can be persisted and restored across launches.
enum WorkspaceSection: Hashable, Codable {
    case overview
    case changes
    case history
    case branch(String)      // local branch — selects history filtered to it (future)
    case remotes
    case tags
    case stashes
    case worktrees
    case reflog
    case submodules
}

/// A repository's workspace: an inner section rail plus the section's content.
struct RepositoryWorkspaceView: View {
    let ref: RepositoryRef
    @State private var viewModel: RepositoryViewModel
    @State private var section: WorkspaceSection
    @State private var integrationSheet: IntegrationSheet?
    @State private var showSettings = false

    // Per-repository key for the last-selected section.
    private var sectionKey: String { SidebarDefaults.sectionKey(ref.path) }

    init(ref: RepositoryRef) {
        self.ref = ref
        _viewModel = State(initialValue: RepositoryViewModel(ref: ref))
        // Restore the section that was open for this repository last time, defaulting to Changes.
        let saved = UserDefaults.standard.data(forKey: SidebarDefaults.sectionKey(ref.path))
            .flatMap { try? JSONDecoder().decode(WorkspaceSection.self, from: $0) }
        _section = State(initialValue: saved ?? .changes)
    }

    var body: some View {
        NavigationSplitView {
            WorkspaceRail(viewModel: viewModel, section: $section, integrationSheet: $integrationSheet)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(sectionTitle) // current view name, shown over the content
        }
        .onChange(of: section) { _, new in
            if let data = try? JSONEncoder().encode(new) {
                UserDefaults.standard.set(data, forKey: sectionKey)
            }
        }
        .background(TitlebarBrand())
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await viewModel.fetch() } } label: {
                    Label("Fetch", systemImage: "arrow.down.circle")
                }
                .help("Fetch from all remotes").disabled(viewModel.isBusy)

                Menu {
                    Button("Pull") { Task { await viewModel.pull() } }
                    Button("Pull with Rebase") { Task { await viewModel.pull(rebase: true) } }
                } label: {
                    Label("Pull", systemImage: "arrow.down.to.line")
                }
                .help("Pull current branch").disabled(viewModel.isBusy || viewModel.remotes.isEmpty)

                Menu {
                    Button("Push") { Task { await viewModel.push() } }
                    Button("Force Push (with lease)") {
                        if Prompt.confirmDestructive(
                            title: "Force push?",
                            message: "This overwrites the remote branch (using --force-with-lease).",
                            confirm: "Force Push") {
                            Task { await viewModel.push(force: true) }
                        }
                    }
                    Button("Push Tags") { Task { await viewModel.pushTags() } }
                } label: {
                    Label("Push", systemImage: "arrow.up.to.line")
                }
                .help("Push current branch").disabled(viewModel.isBusy || viewModel.remotes.isEmpty)

                branchMenu
                moreMenu

                Button { Task { await viewModel.load() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh").disabled(viewModel.isLoading)
            }
        }
        .sheet(item: $integrationSheet) { sheet in
            switch sheet {
            case .merge(let source, let target):
                MergeSheet(viewModel: viewModel, source: source, target: target)
            case .rebase(let branch): RebaseSheet(viewModel: viewModel, branch: branch)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsSheet(viewModel: viewModel) }
        .task { await viewModel.load() }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                if let operation = viewModel.operation {
                    OperationBanner(operation: operation) {
                        Task { await viewModel.abortOperation() }
                    }
                }
                if let error = viewModel.loadError {
                    ErrorBanner(message: error)
                }
            }
        }
        .overlay {
            if viewModel.isBusy {
                OperationOverlay(title: viewModel.operationTitle ?? "Working",
                                 detail: viewModel.operationProgress)
            }
        }
    }

    /// Toolbar "Branch" menu: checkout, new branch, merge, rebase.
    @ViewBuilder
    private var branchMenu: some View {
        let others = viewModel.localBranches.filter { !$0.isHead }
        Menu {
            if !viewModel.localBranches.isEmpty {
                Menu("Checkout") {
                    ForEach(viewModel.localBranches) { branch in
                        Button {
                            Task { await viewModel.checkout(branch.name) }
                        } label: {
                            if branch.isHead { Label(branch.name, systemImage: "checkmark") }
                            else { Text(branch.name) }
                        }
                    }
                }
            }
            Button("New Branch…") { promptNewBranch() }
            Divider()
            Button("Merge into Current Branch…") {
                if let source = others.first?.name, let current = viewModel.currentBranch?.name {
                    integrationSheet = .merge(source: source, target: current)
                }
            }
            .disabled(others.isEmpty || viewModel.currentBranch == nil)
            Button("Rebase Current Branch…") {
                if let target = others.first?.name { integrationSheet = .rebase(target) }
            }
            .disabled(others.isEmpty)
        } label: {
            Label("Branch", systemImage: "arrow.triangle.branch")
        }
        .help("Branch actions")
    }

    /// Toolbar "⋯" menu: repository-level actions (settings, remotes, submodules).
    @ViewBuilder
    private var moreMenu: some View {
        Menu {
            Menu("Remotes") {
                Button("Add Remote…") { promptAddRemote() }
                if !viewModel.remotes.isEmpty {
                    Divider()
                    ForEach(viewModel.remotes) { remote in
                        Menu(remote.name) {
                            Text(remote.fetchURL)
                            Button("Remove “\(remote.name)”", role: .destructive) {
                                Task { await viewModel.removeRemote(remote.name) }
                            }
                        }
                    }
                }
            }
            Button("Add Submodule…") { promptAddSubmodule() }
            Divider()
            Button("Repository Settings…") { showSettings = true }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .help("Repository actions")
    }

    private func promptAddRemote() {
        guard let name = Prompt.text(title: "Add Remote", message: "Remote name (e.g. origin).",
                                     defaultValue: "origin", confirm: "Next") else { return }
        guard let url = Prompt.text(title: "Remote URL", message: "Git URL for “\(name)”.",
                                    confirm: "Add Remote") else { return }
        Task { await viewModel.addRemote(name: name, url: url) }
    }

    private func promptNewBranch() {
        guard let name = Prompt.text(title: "New Branch",
                                     message: "Create and switch to a new branch from HEAD.",
                                     confirm: "Create") else { return }
        Task { await viewModel.createBranch(name: name, checkout: true) }
    }

    private func promptAddSubmodule() {
        guard let url = Prompt.text(title: "Add Submodule",
                                    message: "Git URL of the submodule repository.", confirm: "Next") else { return }
        guard let path = Prompt.text(title: "Submodule Path",
                                     message: "Where to place it, relative to the repo root (e.g. libs/foo).",
                                     confirm: "Add") else { return }
        Task { await viewModel.addSubmodule(url: url, path: path) }
    }

    /// Name of the active section, shown as the title over the content area.
    private var sectionTitle: String {
        switch section {
        case .overview: "Overview"
        case .changes: "Working Tree"
        case .history: "History"
        case .branch(let name): name
        case .remotes: "Remote Branches"
        case .tags: "Tags"
        case .stashes: "Stashes"
        case .worktrees: "Worktrees"
        case .reflog: "Reflog"
        case .submodules: "Submodules"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .overview:
            OverviewView(viewModel: viewModel)
        case .changes:
            WorkingTreeView(viewModel: viewModel)
        case .history, .branch:
            HistoryView(viewModel: viewModel)
        case .remotes:
            RefListView(title: "Remote Branches", refs: viewModel.remoteBranches, symbol: "cloud", viewModel: viewModel)
        case .tags:
            RefListView(title: "Tags", refs: viewModel.tags, symbol: "tag", viewModel: viewModel)
        case .stashes:
            StashesView(viewModel: viewModel)
        case .worktrees:
            WorktreesView(viewModel: viewModel)
        case .reflog:
            ReflogView(viewModel: viewModel)
        case .submodules:
            SubmodulesView(viewModel: viewModel)
        }
    }
}

/// The repo identity header at the top of the sidebar, doubling as a switcher menu.
private struct RepoSwitcher: View {
    let model: AppModel
    let current: RepositoryRef
    @State private var showAccounts = false

    var body: some View {
        Menu {
            ForEach(model.repositories) { repo in
                Button {
                    model.selectedRepositoryID = repo.id
                } label: {
                    if repo.id == current.id {
                        Label(repo.name, systemImage: "checkmark")
                    } else {
                        Text(repo.name)
                    }
                }
            }
            Divider()
            Button("Add Existing Repository…") { Task { await model.promptToAddRepository() } }
            Button("Clone Repository…") { Task { await model.promptToClone() } }
            Divider()
            Button("Accounts…") { showAccounts = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.tint)
                Text(current.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The button menu style draws a pop-up button with the system dropdown chevron,
        // making it clearly switchable.
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .sheet(isPresented: $showAccounts) { AccountsView(model: model) }
    }
}

/// Modal overlay shown during fetch/pull/push, surfacing live git progress lines.
private struct OperationOverlay: View {
    let title: String
    let detail: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView()
                Text(title).font(.headline)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).frame(maxWidth: 320)
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 20)
        }
    }
}

/// A merge/rebase dialog to present, parameterized by the selected branch.
private enum IntegrationSheet: Identifiable {
    /// Merge `source` into `target`. `target` is checked out first if it isn't current.
    case merge(source: String, target: String)
    case rebase(String)
    var id: String {
        switch self {
        case .merge(let s, let t): "merge:\(s)->\(t)"
        case .rebase(let b): "rebase:\(b)"
        }
    }
}

/// The navigation rail: a repo switcher header, section list, and current-branch footer.
private struct WorkspaceRail: View {
    @Environment(AppModel.self) private var model
    let viewModel: RepositoryViewModel
    @Binding var section: WorkspaceSection
    @Binding var integrationSheet: IntegrationSheet?

    // Titles of collapsed top-level sections, seeded from and persisted to UserDefaults so the
    // sidebar reopens with the same sections expanded/collapsed as last time.
    @State private var collapsedSections: Set<String>
    private let sectionsKey: String

    init(viewModel: RepositoryViewModel, section: Binding<WorkspaceSection>,
         integrationSheet: Binding<IntegrationSheet?>) {
        self.viewModel = viewModel
        self._section = section
        self._integrationSheet = integrationSheet
        let key = SidebarDefaults.sectionsKey(viewModel.ref.path)
        self.sectionsKey = key
        self._collapsedSections = State(initialValue: Set(UserDefaults.standard.stringArray(forKey: key) ?? []))
    }

    /// A binding to a section's expanded state, backed by `collapsedSections` and persisted.
    private func expanded(_ title: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedSections.contains(title) },
            set: { isExpanded in
                if isExpanded { collapsedSections.remove(title) } else { collapsedSections.insert(title) }
                UserDefaults.standard.set(Array(collapsedSections), forKey: sectionsKey)
            }
        )
    }

    var body: some View {
        List(selection: $section) {
            Section("Repository", isExpanded: expanded("Repository")) {
                Label("Overview", systemImage: "info.circle").tag(WorkspaceSection.overview)
                Label {
                    HStack {
                        Text("Changes")
                        Spacer()
                        if let count = viewModel.status?.files.count, count > 0 {
                            CountBadge(count: count)
                        }
                    }
                } icon: { Image(systemName: "pencil.and.list.clipboard") }
                .tag(WorkspaceSection.changes)
                Label("History", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(WorkspaceSection.history)
                Label {
                    HStack {
                        Text("Worktrees")
                        Spacer()
                        if viewModel.worktrees.count > 1 { CountBadge(count: viewModel.worktrees.count) }
                    }
                } icon: { Image(systemName: "square.split.2x1") }
                .tag(WorkspaceSection.worktrees)
                Label {
                    HStack {
                        Text("Stashes")
                        Spacer()
                        if !viewModel.stashes.isEmpty { CountBadge(count: viewModel.stashes.count) }
                    }
                } icon: { Image(systemName: "tray.full") }
                .tag(WorkspaceSection.stashes)
                if !viewModel.submodules.isEmpty {
                    Label {
                        HStack {
                            Text("Submodules")
                            Spacer()
                            CountBadge(count: viewModel.submodules.count)
                        }
                    } icon: { Image(systemName: "shippingbox.and.arrow.backward") }
                    .tag(WorkspaceSection.submodules)
                }
            }

            Section("Local", isExpanded: expanded("Local")) {
                // Branches with "/" in their name are grouped into expandable folders.
                // Rendered as a single compact row (see BranchTreeList) so leaves sit close.
                BranchTreeList(nodes: BranchNode.tree(from: viewModel.localBranches),
                               viewModel: viewModel, selection: $section,
                               integrationSheet: $integrationSheet)
            }

            Section("Remote", isExpanded: expanded("Remote")) {
                if viewModel.remoteBranches.isEmpty {
                    Label("Remote Branches", systemImage: "cloud").tag(WorkspaceSection.remotes)
                        .contextMenu { remoteMenu }
                } else {
                    // Same tree as Local: the remote name (e.g. origin) is the top folder.
                    // Drop the symbolic "<remote>/HEAD" ref — it's a pointer, not a branch.
                    let remotes = viewModel.remoteBranches.filter { !$0.name.hasSuffix("/HEAD") }
                    BranchTreeList(nodes: BranchNode.tree(from: remotes), viewModel: viewModel,
                                   selection: $section, integrationSheet: $integrationSheet,
                                   isRemote: true, folderIcon: "cloud")
                }
            }
            Section("Tags", isExpanded: expanded("Tags")) {
                Label("Tags", systemImage: "tag").tag(WorkspaceSection.tags)
            }
            Section("Reflog", isExpanded: expanded("Reflog")) {
                Label("Reflog", systemImage: "clock.arrow.circlepath").tag(WorkspaceSection.reflog)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            RepoSwitcher(model: model, current: viewModel.ref)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let branch = viewModel.currentBranch {
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(.secondary)
                        Text(branch.name).fontWeight(.medium)
                        if let ahead = branch.ahead, let behind = branch.behind, ahead + behind > 0 {
                            Text("↑\(ahead) ↓\(behind)").foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .font(.caption)
                    .padding(.leading, 30) // line the icon up with the sidebar row icons
                    .padding(.trailing, 14)
                    .padding(.vertical, 8)
                }
                .background(.bar)
            }
        }
    }

    /// Context menu for the "Remote Branches" rail entry.
    @ViewBuilder
    private var remoteMenu: some View {
        Button("Add Remote…") {
            guard let name = Prompt.text(title: "Add Remote", message: "Remote name (e.g. origin).",
                                         defaultValue: "origin", confirm: "Next") else { return }
            guard let url = Prompt.text(title: "Remote URL", message: "Git URL for “\(name)”.",
                                        confirm: "Add Remote") else { return }
            Task { await viewModel.addRemote(name: name, url: url) }
        }
        if !viewModel.remotes.isEmpty {
            Divider()
            ForEach(viewModel.remotes) { remote in
                Button("Remove “\(remote.name)”", role: .destructive) {
                    Task { await viewModel.removeRemote(remote.name) }
                }
            }
        }
    }

}

/// A node in the local-branch tree: either a leaf branch (`ref` set) or a folder grouping
/// branches that share a "<prefix>/" path.
struct BranchNode: Identifiable {
    let id: String
    let name: String
    let ref: Ref?
    let children: [BranchNode]

    /// Builds a tree from branch names, splitting on "/" into folders.
    static func tree(from refs: [Ref]) -> [BranchNode] {
        typealias Item = (segments: [String], ref: Ref)
        let items: [Item] = refs.map { ($0.name.split(separator: "/").map(String.init), $0) }

        func make(_ items: [Item], prefix: String) -> [BranchNode] {
            Dictionary(grouping: items, by: { $0.segments.first ?? "" })
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { segment, group in
                    let full = prefix.isEmpty ? segment : "\(prefix)/\(segment)"
                    if group.count == 1, group[0].segments.count == 1 {
                        return BranchNode(id: full, name: segment, ref: group[0].ref, children: [])
                    }
                    let deeper: [Item] = group.map { (Array($0.segments.dropFirst()), $0.ref) }
                    return BranchNode(id: full, name: segment, ref: nil, children: make(deeper, prefix: full))
                }
        }
        return make(items, prefix: "")
    }
}

/// The whole branch tree rendered as a single List row, so its leaf rows can be tighter
/// than the fixed sidebar row metric while the rest of the sidebar keeps its native style.
/// Selection is drawn manually (a capsule matching the sidebar highlight).
private struct BranchTreeList: View {
    let nodes: [BranchNode]
    let viewModel: RepositoryViewModel
    @Binding var selection: WorkspaceSection
    @Binding var integrationSheet: IntegrationSheet?
    var isRemote = false
    var folderIcon = "folder"
    // Which folders are collapsed. Seeded from UserDefaults so the tree reopens the same way.
    @State private var collapsed: Set<String>
    // Per-repository, per-tree key under which the collapsed folder set is persisted.
    private let persistenceKey: String

    init(nodes: [BranchNode], viewModel: RepositoryViewModel,
         selection: Binding<WorkspaceSection>, integrationSheet: Binding<IntegrationSheet?>,
         isRemote: Bool = false, folderIcon: String = "folder") {
        self.nodes = nodes
        self.viewModel = viewModel
        self._selection = selection
        self._integrationSheet = integrationSheet
        self.isRemote = isRemote
        self.folderIcon = folderIcon
        let key = SidebarDefaults.collapsedKey(viewModel.ref.path, isRemote: isRemote)
        self.persistenceKey = key
        let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
        self._collapsed = State(initialValue: Set(saved))
    }

    /// Mutating through this binding persists the collapsed set on every toggle.
    private var collapsedBinding: Binding<Set<String>> {
        Binding(
            get: { collapsed },
            set: { new in
                collapsed = new
                UserDefaults.standard.set(Array(new), forKey: persistenceKey)
            }
        )
    }

    /// A single visible row: a node plus its depth. Folders hide their descendants when collapsed.
    private struct Row: Identifiable {
        let node: BranchNode
        let depth: Int
        var id: String { node.id }
    }

    /// Flattens the tree into the rows currently visible, so each can be emitted as its own List
    /// row — that's what makes per-leaf right-click and selection work (a single cell can't).
    private var visibleRows: [Row] {
        var out: [Row] = []
        func walk(_ ns: [BranchNode], _ depth: Int) {
            for n in ns {
                out.append(Row(node: n, depth: depth))
                if n.ref == nil && !collapsed.contains(n.id) { walk(n.children, depth + 1) }
            }
        }
        walk(nodes, 0)
        return out
    }

    var body: some View {
        ForEach(visibleRows) { row in
            BranchTreeRow(node: row.node, viewModel: viewModel, selection: $selection,
                          integrationSheet: $integrationSheet, collapsed: collapsedBinding,
                          isRemote: isRemote,
                          folderIcon: row.depth == 0 ? folderIcon : "folder", depth: row.depth)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
        }
    }
}

/// One node within `BranchTreeList`: a selectable branch leaf, or an expandable folder.
/// Tight vertical padding gives close leaf spacing; depth drives indentation.
private struct BranchTreeRow: View {
    let node: BranchNode
    let viewModel: RepositoryViewModel
    @Binding var selection: WorkspaceSection
    @Binding var integrationSheet: IntegrationSheet?
    @Binding var collapsed: Set<String>
    var isRemote = false
    var folderIcon = "folder"
    var depth: Int

    // Leading inset of this row's first glyph (chevron for folders, branch icon for leaves).
    // `base` lines the depth-0 chevron up with the sidebar's section icons above; each folder
    // level adds `step`; leaves sit an extra `leafInset` past their folder so they read as
    // clearly nested inside it.
    private var indent: CGFloat {
        let base: CGFloat = 4, step: CGFloat = 16, leafInset: CGFloat = 26
        if node.ref != nil {
            return depth == 0 ? base : base + CGFloat(depth - 1) * step + leafInset
        }
        return base + CGFloat(depth) * step
    }
    private var expanded: Bool { !collapsed.contains(node.id) }
    // Root rows match the main sidebar row pitch; nested rows stay tightly grouped.
    private var vpad: CGFloat { depth == 0 ? 8 : 3 }

    var body: some View {
        if let ref = node.ref {
            let isSelected = selection == .branch(ref.name)
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch").frame(width: 16)
                Text(node.name).lineLimit(1)
                Spacer(minLength: 4)
                if !isRemote, let ahead = ref.ahead, let behind = ref.behind, ahead + behind > 0 {
                    Text("↑\(ahead) ↓\(behind)").font(.caption2)
                        .foregroundStyle(isSelected ? .white : .secondary)
                }
                if ref.isHead {
                    Image(systemName: "checkmark").foregroundStyle(isSelected ? .white : .secondary)
                }
            }
            .padding(.vertical, vpad)
            .padding(.leading, indent)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : .clear)
                    // Extend the highlight closer to the sidebar's left edge; keep a
                    // small trailing inset so it doesn't touch the right edge.
                    .padding(.leading, 0)
                    .padding(.trailing, 6)
            )
            .contentShape(Rectangle())
            .onTapGesture { selection = .branch(ref.name) }
            // Each branch is now its own List row, so a per-row menu targets exactly this leaf.
            .contextMenu {
                if isRemote {
                    RemoteBranchMenu(branch: ref, viewModel: viewModel)
                } else {
                    BranchContextMenu(branch: ref, viewModel: viewModel, integrationSheet: $integrationSheet)
                }
            }
        } else {
            // Folder header row. Children are emitted as sibling List rows by BranchTreeList's
            // flattening, so this renders only the header (no nested content here).
            HStack(spacing: 4) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption2).foregroundStyle(.secondary).frame(width: 12)
                Image(systemName: folderIcon).frame(width: 16)
                Text(node.name).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, vpad)
            .padding(.leading, indent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if expanded { collapsed.insert(node.id) } else { collapsed.remove(node.id) }
            }
        }
    }
}

/// Right-click actions for a remote-tracking branch.
private struct RemoteBranchMenu: View {
    let branch: Ref
    let viewModel: RepositoryViewModel

    var body: some View {
        Button("Checkout as Local Branch") { Task { await viewModel.checkout(branch.name) } }
        Divider()
        Button("Delete Remote Branch…", role: .destructive) {
            guard let slash = branch.name.firstIndex(of: "/") else { return }
            let remote = String(branch.name[..<slash])
            let name = String(branch.name[branch.name.index(after: slash)...])
            if Prompt.confirmDestructive(title: "Delete “\(branch.name)” on the remote?",
                                         message: "This deletes the branch on \(remote).", confirm: "Delete") {
                Task { await viewModel.deleteRemoteBranch(remote: remote, branch: name) }
            }
        }
    }
}

/// Right-click actions for a local branch.
private struct BranchContextMenu: View {
    let branch: Ref
    let viewModel: RepositoryViewModel
    @Binding var integrationSheet: IntegrationSheet?

    var body: some View {
        if !branch.isHead {
            let current = viewModel.currentBranch?.name
            Button("Checkout") { Task { await viewModel.checkout(branch.name) } }
            Divider()
            // Merge this branch into the one you're on.
            Button("Merge into “\(current ?? "current")”…") {
                if let current { integrationSheet = .merge(source: branch.name, target: current) }
            }
            .disabled(current == nil)
            // Reverse direction: merge the branch you're on into this one (checks it out first),
            // so you can merge e.g. a feature into main without switching branches first.
            Button("Merge “\(current ?? "current")” into “\(branch.name)”…") {
                if let current { integrationSheet = .merge(source: current, target: branch.name) }
            }
            .disabled(current == nil)
            Button("Rebase “\(current ?? "current")” onto This…") {
                integrationSheet = .rebase(branch.name)
            }
            Divider()
        }
        Button("Rename…") {
            if let name = Prompt.text(title: "Rename Branch", defaultValue: branch.name, confirm: "Rename") {
                Task { await viewModel.renameBranch(branch, to: name) }
            }
        }
        Button("New Branch from Here…") {
            if let name = Prompt.text(title: "New Branch", message: "Create from \(branch.name).", confirm: "Create") {
                Task { await viewModel.createBranch(name: name, checkout: true) }
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            guard !branch.isHead else {
                _ = Prompt.confirmDestructive(title: "Can’t Delete Current Branch",
                                              message: "Check out another branch first.", confirm: "OK")
                return
            }
            if Prompt.confirmDestructive(title: "Delete “\(branch.name)”?",
                                         message: "This removes the local branch.", confirm: "Delete") {
                Task { await viewModel.forceDeleteBranch(branch) }
            }
        }
        .disabled(branch.isHead)
    }
}

struct CountBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(.quaternary))
    }
}

private struct ErrorBanner: View {
    let message: String
    var body: some View {
        Text(message)
            .font(.callout)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(.red.opacity(0.15))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(.red.opacity(0.3)), alignment: .bottom)
    }
}

/// Shown while a conflicted merge/rebase is in progress, offering to abort.
private struct OperationBanner: View {
    let operation: RepositoryOperation
    let onAbort: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("\(operation.rawValue.capitalized) in progress — resolve conflicts and commit, or abort.")
            Spacer()
            Button("Abort \(operation.rawValue.capitalized)", role: .destructive, action: onAbort)
                .controlSize(.small)
        }
        .font(.callout)
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.orange.opacity(0.15))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(.orange.opacity(0.4)), alignment: .bottom)
    }
}
