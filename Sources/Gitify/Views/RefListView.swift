import SwiftUI
import GitKit

/// Generic list of refs (remote branches or tags), with context actions.
struct RefListView: View {
    let title: String
    let refs: [Ref]
    let symbol: String
    let viewModel: RepositoryViewModel

    var body: some View {
        VStack(spacing: 0) {
            if refs.isEmpty {
                ContentUnavailableView(title, systemImage: symbol,
                                       description: Text("Nothing here yet."))
            } else {
                List(refs) { ref in
                    HStack(spacing: 8) {
                        Image(systemName: symbol).foregroundStyle(.secondary)
                        Text(ref.name)
                        Spacer()
                        Text(ref.targetSHA.prefix(7)).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    .contextMenu { menu(for: ref) }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
        .safeAreaInset(edge: .top) {
            if isTags {
                HStack {
                    Button { createTag() } label: { Label("New Tag", systemImage: "tag") }
                    Spacer()
                }
                .padding(8).background(.bar)
            }
        }
    }

    private var isTags: Bool { refs.first?.kind == .tag || title == "Tags" }

    @ViewBuilder
    private func menu(for ref: Ref) -> some View {
        switch ref.kind {
        case .remoteBranch:
            Button("Checkout as Local Branch") {
                Task { await viewModel.checkout(ref.name) }
            }
        case .tag:
            Button("Checkout") { Task { await viewModel.checkout(ref.name) } }
            Divider()
            Button("Delete Tag", role: .destructive) {
                if Prompt.confirmDestructive(title: "Delete tag “\(ref.name)”?",
                                             message: "This removes the local tag.", confirm: "Delete") {
                    Task { await viewModel.deleteTag(ref) }
                }
            }
        case .localBranch:
            Button("Checkout") { Task { await viewModel.checkout(ref.name) } }
        }
    }

    private func createTag() {
        guard let name = Prompt.text(title: "New Tag", message: "Create a tag at HEAD.", confirm: "Create") else { return }
        let message = Prompt.text(title: "Tag Message", message: "Optional — leave empty for a lightweight tag.",
                                  confirm: "Create", allowEmpty: true)
        Task { await viewModel.createTag(name: name, on: nil, message: (message?.isEmpty == false) ? message : nil) }
    }
}
