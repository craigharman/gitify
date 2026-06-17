import SwiftUI
import GitKit

/// Generic list of refs (remote branches or tags), with context actions.
struct RefListView: View {
    let title: String
    let refs: [Ref]
    let symbol: String
    let viewModel: RepositoryViewModel
    @State private var search = ""

    private var filtered: [Ref] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? refs : refs.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if refs.isEmpty {
                ContentUnavailableView(title, systemImage: symbol,
                                       description: Text("Nothing here yet."))
            } else {
                SearchField(text: $search, prompt: "Filter \(title.lowercased())")
                List(filtered) { ref in
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
            Divider()
            Button("Delete Remote Branch…", role: .destructive) {
                // ref.name is "<remote>/<branch>"; split into remote + branch.
                guard let slash = ref.name.firstIndex(of: "/") else { return }
                let remote = String(ref.name[..<slash])
                let branch = String(ref.name[ref.name.index(after: slash)...])
                if Prompt.confirmDestructive(title: "Delete “\(ref.name)” on the remote?",
                                             message: "This deletes the branch on \(remote).", confirm: "Delete") {
                    Task { await viewModel.deleteRemoteBranch(remote: remote, branch: branch) }
                }
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
