import SwiftUI
import GitKit

struct StashesView: View {
    let viewModel: RepositoryViewModel
    @State private var selection: Stash.ID?

    var body: some View {
        if viewModel.stashes.isEmpty {
            emptyState
        } else {
            HSplitView {
                stashList
                    .frame(minWidth: 280, idealWidth: 320)
                if let stash = viewModel.stashes.first(where: { $0.id == selection }) {
                    ChangesetDiffPane(ref: stash.id, viewModel: viewModel)
                        .id(stash.id)
                        .frame(minWidth: 360, maxWidth: .infinity)
                } else {
                    ContentUnavailableView("No Stash Selected", systemImage: "tray.full")
                        .frame(minWidth: 360, maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var stashList: some View {
        List(selection: $selection) {
            ForEach(viewModel.stashes) { stash in
                VStack(alignment: .leading, spacing: 1) {
                    Text(stash.message).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(stash.id).monospaced()
                        if let branch = stash.branch { Text("on \(branch)") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(stash.id)
                .contextMenu { menu(for: stash) }
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .top) {
            HStack {
                Button { stashChanges() } label: { Label("Stash Changes", systemImage: "tray.and.arrow.down") }
                    .disabled(viewModel.status?.hasChanges != true)
                Spacer()
            }
            .padding(8).background(.bar)
        }
    }

    @ViewBuilder
    private func menu(for stash: Stash) -> some View {
        Button("Apply") { Task { await viewModel.applyStash(stash) } }
        Button("Pop") { Task { await viewModel.popStash(stash) } }
        Button("Create Branch from Stash…") {
            if let name = Prompt.text(title: "Branch from Stash",
                                      message: "Create a branch and apply \(stash.id).", confirm: "Create") {
                Task { await viewModel.branchFromStash(stash, name: name) }
            }
        }
        Divider()
        Button("Drop", role: .destructive) {
            if Prompt.confirmDestructive(title: "Drop “\(stash.id)”?",
                                         message: "This discards the stashed changes.", confirm: "Drop") {
                Task { await viewModel.dropStash(stash) }
            }
        }
    }

    private var emptyState: some View {
        VStack {
            ContentUnavailableView("No Stashes", systemImage: "tray.full",
                                   description: Text("Stashed changes will appear here."))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top) {
            HStack {
                Button { stashChanges() } label: { Label("Stash Changes", systemImage: "tray.and.arrow.down") }
                    .disabled(viewModel.status?.hasChanges != true)
                Spacer()
            }
            .padding(8).background(.bar)
        }
    }

    private func stashChanges() {
        guard let message = Prompt.text(
            title: "Stash Changes",
            message: "Save working-tree changes (including untracked). Message optional.",
            confirm: "Stash", allowEmpty: true) else { return }
        Task { await viewModel.stashChanges(message: message.isEmpty ? nil : message) }
    }
}
