import SwiftUI
import GitKit

/// Sections available within a repository, mirroring the left rail in the mockups.
enum WorkspaceSection: Hashable {
    case overview
    case changes
    case history
    case branch(String)      // local branch — selects history filtered to it (future)
    case remotes
    case tags
    case stashes
    case worktrees
    case reflog
}

/// A repository's workspace: an inner section rail plus the section's content.
struct RepositoryWorkspaceView: View {
    let ref: RepositoryRef
    @State private var viewModel: RepositoryViewModel
    @State private var section: WorkspaceSection = .changes

    init(ref: RepositoryRef) {
        self.ref = ref
        _viewModel = State(initialValue: RepositoryViewModel(ref: ref))
    }

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceRail(viewModel: viewModel, section: $section)
                .frame(width: 220)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(ref.name)
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await viewModel.fetch() } } label: {
                    Label("Fetch", systemImage: "arrow.down.circle")
                }
                .help("Fetch from all remotes").disabled(viewModel.isBusy)

                Button { Task { await viewModel.pull() } } label: {
                    Label("Pull", systemImage: "arrow.down.to.line")
                }
                .help("Pull current branch").disabled(viewModel.isBusy || viewModel.remotes.isEmpty)

                Button { Task { await viewModel.push() } } label: {
                    Label("Push", systemImage: "arrow.up.to.line")
                }
                .help("Push current branch").disabled(viewModel.isBusy || viewModel.remotes.isEmpty)

                Button { promptNewBranch() } label: {
                    Label("New Branch", systemImage: "plus.square.on.square")
                }
                .help("Create a branch")

                Button { Task { await viewModel.load() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh").disabled(viewModel.isLoading)
            }
        }
        .task { await viewModel.load() }
        .overlay(alignment: .top) {
            if let error = viewModel.loadError {
                ErrorBanner(message: error)
            }
        }
        .overlay {
            if viewModel.isBusy {
                OperationOverlay(title: viewModel.operationTitle ?? "Working",
                                 detail: viewModel.operationProgress)
            }
        }
    }

    private func promptNewBranch() {
        guard let name = Prompt.text(title: "New Branch",
                                     message: "Create and switch to a new branch from HEAD.",
                                     confirm: "Create") else { return }
        Task { await viewModel.createBranch(name: name, checkout: true) }
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
        }
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

/// The inner navigation rail listing sections and ref groups.
private struct WorkspaceRail: View {
    let viewModel: RepositoryViewModel
    @Binding var section: WorkspaceSection

    var body: some View {
        List(selection: $section) {
            Section("Repository") {
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
            }

            Section("Local") {
                ForEach(viewModel.localBranches) { branch in
                    Label {
                        HStack {
                            Text(branch.name)
                            Spacer()
                            if let ahead = branch.ahead, let behind = branch.behind, ahead + behind > 0 {
                                Text("↑\(ahead) ↓\(behind)").font(.caption2).foregroundStyle(.secondary)
                            }
                            if branch.isHead { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                        }
                    } icon: {
                        Image(systemName: "arrow.triangle.branch")
                    }
                    .tag(WorkspaceSection.branch(branch.name))
                    .contextMenu { branchMenu(branch) }
                }
            }

            Section("Remote") {
                Label("Remote Branches", systemImage: "cloud").tag(WorkspaceSection.remotes)
            }
            Section("Tags") {
                Label("Tags", systemImage: "tag").tag(WorkspaceSection.tags)
            }
            Section("Reflog") {
                Label("Reflog", systemImage: "clock.arrow.circlepath").tag(WorkspaceSection.reflog)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if let branch = viewModel.currentBranch {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                    Text(branch.name).fontWeight(.medium)
                    if let ahead = branch.ahead, let behind = branch.behind, ahead + behind > 0 {
                        Text("↑\(ahead) ↓\(behind)").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .font(.caption)
                .padding(8)
                .background(.bar)
            }
        }
    }

    @ViewBuilder
    private func branchMenu(_ branch: Ref) -> some View {
        if !branch.isHead {
            Button("Checkout") { Task { await viewModel.checkout(branch.name) } }
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
