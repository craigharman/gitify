import SwiftUI
import GitKit

/// Working-tree / staging view (Screenshot 3): staged and unstaged file lists.
struct WorkingTreeView: View {
    let viewModel: RepositoryViewModel

    var body: some View {
        if let status = viewModel.status {
            if status.hasChanges {
                List {
                    let staged = status.stagedFiles
                    if !staged.isEmpty {
                        Section("Staged (\(staged.count))") {
                            ForEach(staged) { FileRow(file: $0) }
                        }
                    }
                    let unstaged = status.unstagedFiles
                    if !unstaged.isEmpty {
                        Section("Changes (\(unstaged.count))") {
                            ForEach(unstaged) { FileRow(file: $0) }
                        }
                    }
                }
                .listStyle(.inset)
            } else {
                ContentUnavailableView("Clean Working Tree",
                                       systemImage: "checkmark.seal",
                                       description: Text("There are no changes to commit."))
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// One changed file with its status badge.
struct FileRow: View {
    let file: FileStatus

    var body: some View {
        HStack(spacing: 8) {
            StatusBadge(file: file)
            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: file.path).lastPathComponent)
                if let original = file.originalPath {
                    Text("\(original) → \(file.path)").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(file.path).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

/// Colored M/A/D/R/?? badge mirroring git's status letters.
struct StatusBadge: View {
    let file: FileStatus

    private var letter: String {
        if file.isConflicted { return "U" }
        if file.isUntracked { return "?" }
        let state = file.isStaged ? file.indexState : file.worktreeState
        return String(state.rawValue).uppercased()
    }

    private var color: Color {
        switch letter {
        case "A", "?": return .green
        case "M", "T": return .yellow
        case "D": return .red
        case "R", "C": return .blue
        case "U": return .orange
        default: return .secondary
        }
    }

    var body: some View {
        Text(letter)
            .font(.caption.monospaced().bold())
            .frame(width: 18, height: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.2)))
            .foregroundStyle(color)
    }
}
