import SwiftUI

/// The leftmost sidebar: the list of added repositories (Screenshot 1).
struct RepositoryListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedRepositoryID) {
            Section("Repositories") {
                ForEach(model.repositories) { repo in
                    Label(repo.name, systemImage: "shippingbox")
                        .tag(repo.id)
                        .contextMenu {
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([repo.url])
                            }
                            Button("Remove", role: .destructive) {
                                model.remove(repo)
                            }
                        }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    Task { await model.promptToAddRepository() }
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add Repository")
                Spacer()
            }
            .padding(8)
            .background(.bar)
        }
        .navigationTitle("Gitify")
    }
}
