import SwiftUI
import GitKit

struct SubmodulesView: View {
    let viewModel: RepositoryViewModel

    var body: some View {
        Group {
            if viewModel.submodules.isEmpty {
                ContentUnavailableView("No Submodules", systemImage: "shippingbox.and.arrow.backward",
                                       description: Text("This repository has no submodules."))
            } else {
                List(viewModel.submodules) { submodule in
                    HStack(spacing: 8) {
                        Image(systemName: "shippingbox").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(submodule.path).fontWeight(.medium)
                                if !submodule.isInitialized { TagLabel("not initialized", color: .orange) }
                                if submodule.isModified { TagLabel("modified", color: .yellow) }
                                if submodule.hasConflicts { TagLabel("conflicts", color: .red) }
                            }
                            HStack(spacing: 6) {
                                Text(submodule.sha.prefix(7)).monospaced()
                                if let ref = submodule.ref { Text(ref) }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Update") { Task { await viewModel.updateSubmodules(path: submodule.path) } }
                            .buttonStyle(.borderless).font(.caption)
                    }
                    .padding(.vertical, 2)
                    .contextMenu {
                        Button("Update / Init") { Task { await viewModel.updateSubmodules(path: submodule.path) } }
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [viewModel.ref.url.appendingPathComponent(submodule.path)])
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top) {
            HStack {
                Button { Task { await viewModel.updateSubmodules(path: nil) } } label: {
                    Label("Update All", systemImage: "arrow.triangle.2.circlepath")
                }
                Button { addSubmodule() } label: { Label("Add", systemImage: "plus") }
                Spacer()
            }
            .padding(8).background(.bar)
        }
    }

    private func addSubmodule() {
        guard let url = Prompt.text(title: "Add Submodule",
                                    message: "Git URL of the submodule repository.", confirm: "Next") else { return }
        guard let path = Prompt.text(title: "Submodule Path",
                                     message: "Where to place it, relative to the repo root (e.g. libs/foo).",
                                     confirm: "Add") else { return }
        Task { await viewModel.addSubmodule(url: url, path: path) }
    }
}
