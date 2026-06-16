import SwiftUI
import GitKit

struct WorktreesView: View {
    let viewModel: RepositoryViewModel

    var body: some View {
        List(viewModel.worktrees) { worktree in
            HStack(spacing: 8) {
                Image(systemName: worktree.isMain ? "house" : "square.split.2x1")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(worktree.branch ?? (worktree.isDetached ? "detached" : "—"))
                            .fontWeight(.medium)
                        if worktree.isMain { TagLabel("main", color: .blue) }
                        if worktree.isLocked { TagLabel("locked", color: .orange) }
                    }
                    Text(worktree.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let head = worktree.head {
                    Text(head.prefix(7)).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            .contextMenu {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: worktree.path)])
                }
                if !worktree.isMain {
                    Button("Remove…", role: .destructive) {
                        if Prompt.confirmDestructive(
                            title: "Remove Worktree?",
                            message: "Removes the worktree at \(worktree.path).", confirm: "Remove") {
                            Task { await viewModel.removeWorktree(worktree) }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .top) {
            HStack {
                Button { addWorktree() } label: {
                    Label("Add Worktree", systemImage: "plus.square.on.square")
                }
                Spacer()
            }
            .padding(8)
            .background(.bar)
        }
    }

    private func addWorktree() {
        guard let parent = Prompt.chooseDirectory(prompt: "Choose Location",
                                                  message: "Pick a parent folder for the new worktree") else { return }
        guard let branch = Prompt.text(title: "New Worktree",
                                       message: "Create a worktree checking out a new branch.",
                                       defaultValue: "worktree-branch", confirm: "Create") else { return }
        let path = parent.appendingPathComponent(branch).path
        Task { await viewModel.addWorktree(path: path, branch: branch, create: true) }
    }
}

struct TagLabel: View {
    let text: String
    let color: Color
    init(_ text: String, color: Color) { self.text = text; self.color = color }
    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.2)))
            .foregroundStyle(color)
    }
}
