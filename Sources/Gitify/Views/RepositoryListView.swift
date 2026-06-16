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
                Menu {
                    Button("Add Existing Repository…") { Task { await model.promptToAddRepository() } }
                    Button("Clone Repository…") { Task { await model.promptToClone() } }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help("Add or clone a repository")
                Spacer()
            }
            .padding(8)
            .background(.bar)
        }
        .navigationTitle("Gitify")
    }
}
