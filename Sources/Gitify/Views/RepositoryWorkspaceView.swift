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
                Button {
                    Task { await viewModel.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                .disabled(viewModel.isLoading)
            }
        }
        .task { await viewModel.load() }
        .overlay(alignment: .top) {
            if let error = viewModel.loadError {
                ErrorBanner(message: error)
            }
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
            RefListView(title: "Remote Branches", refs: viewModel.remoteBranches, symbol: "cloud")
        case .tags:
            RefListView(title: "Tags", refs: viewModel.tags, symbol: "tag")
        case .stashes:
            StashesView(viewModel: viewModel)
        case .worktrees:
            WorktreesView(viewModel: viewModel)
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
                            if branch.isHead { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                        }
                    } icon: {
                        Image(systemName: "arrow.triangle.branch")
                    }
                    .tag(WorkspaceSection.branch(branch.name))
                }
            }

            Section("Remote") {
                Label("Remote Branches", systemImage: "cloud").tag(WorkspaceSection.remotes)
            }
            Section("Tags") {
                Label("Tags", systemImage: "tag").tag(WorkspaceSection.tags)
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
