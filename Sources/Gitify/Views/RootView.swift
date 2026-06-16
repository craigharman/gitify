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
        .overlay {
            if model.isCloning {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Cloning…").font(.headline)
                        if let progress = model.cloneProgress, !progress.isEmpty {
                            Text(progress).font(.caption.monospaced()).foregroundStyle(.secondary)
                                .lineLimit(1).frame(maxWidth: 320)
                        }
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 20)
                }
            }
        }
    }
}
