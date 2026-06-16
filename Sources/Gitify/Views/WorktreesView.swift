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
        }
        .listStyle(.inset)
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
