import SwiftUI

/// Top-level three-column layout: repository list, repository workspace.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            RepositoryListView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            if let ref = model.selectedRepository {
                // Recreate the workspace when the selected repository changes.
                RepositoryWorkspaceView(ref: ref)
                    .id(ref.id)
            } else {
                ContentUnavailableView {
                    Label("No Repository", systemImage: "folder.badge.gearshape")
                } description: {
                    Text("Add a Git repository to get started.")
                } actions: {
                    Button("Add Repository…") {
                        Task { await model.promptToAddRepository() }
                    }
                }
            }
        }
    }
}
