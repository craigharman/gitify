import SwiftUI
import GitKit

struct StashesView: View {
    let viewModel: RepositoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.stashes.isEmpty {
                ContentUnavailableView("No Stashes", systemImage: "tray.full",
                                       description: Text("Stashed changes will appear here."))
            } else {
                List(viewModel.stashes) { stash in
                    HStack(spacing: 8) {
                        Image(systemName: "tray.full").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stash.message).lineLimit(1)
                            HStack(spacing: 6) {
                                Text(stash.id).monospaced()
                                if let branch = stash.branch { Text("on \(branch)") }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button("Apply") { Task { await viewModel.applyStash(stash) } }
                        Button("Pop") { Task { await viewModel.popStash(stash) } }
                        Divider()
                        Button("Drop", role: .destructive) {
                            if Prompt.confirmDestructive(title: "Drop “\(stash.id)”?",
                                                         message: "This discards the stashed changes.",
                                                         confirm: "Drop") {
                                Task { await viewModel.dropStash(stash) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top) {
            HStack {
                Button {
                    guard let message = Prompt.text(
                        title: "Stash Changes",
                        message: "Save working-tree changes (including untracked). Message optional.",
                        confirm: "Stash", allowEmpty: true) else { return }
                    Task { await viewModel.stashChanges(message: message.isEmpty ? nil : message) }
                } label: {
                    Label("Stash Changes", systemImage: "tray.and.arrow.down")
                }
                .disabled(viewModel.status?.hasChanges != true)
                Spacer()
            }
            .padding(8)
            .background(.bar)
        }
    }
}
