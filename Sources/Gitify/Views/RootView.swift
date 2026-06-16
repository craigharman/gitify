import SwiftUI

/// Top-level container: the workspace for the selected repository (which owns its own
/// sidebar + detail split), or an empty state when no repository is open.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let ref = model.selectedRepository {
                // Recreate the workspace when the selected repository changes.
                RepositoryWorkspaceView(ref: ref)
                    .id(ref.id)
            } else {
                ContentUnavailableView {
                    Label("No Repository", systemImage: "folder.badge.gearshape")
                } description: {
                    Text("Add or clone a Git repository to get started.")
                } actions: {
                    Button("Add Repository…") { Task { await model.promptToAddRepository() } }
                    Button("Clone Repository…") { Task { await model.promptToClone() } }
                }
            }
        }
        .task {
            // Quiet check on launch; surfaces a prompt only if a newer version exists.
            await UpdateChecker.checkForUpdates(userInitiated: false)
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
