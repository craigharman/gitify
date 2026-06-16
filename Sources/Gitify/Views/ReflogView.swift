import SwiftUI
import GitKit

/// Lists recent HEAD reflog entries — a safety net for finding "lost" commits.
struct ReflogView: View {
    let viewModel: RepositoryViewModel

    var body: some View {
        if viewModel.reflog.isEmpty {
            ContentUnavailableView("No Reflog", systemImage: "clock.arrow.circlepath",
                                   description: Text("HEAD movements will appear here."))
        } else {
            List(viewModel.reflog) { entry in
                HStack(spacing: 8) {
                    Text(entry.selector)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 84, alignment: .leading)
                    ActionTag(text: entry.action)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.message.isEmpty ? entry.action : entry.message).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(entry.sha.prefix(7)).monospaced()
                            Text(entry.date, format: .relative(presentation: .named))
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
                .contextMenu {
                    Button("Copy SHA") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.sha, forType: .string)
                    }
                    Button("Checkout This State") { Task { await viewModel.checkout(entry.sha) } }
                }
            }
            .listStyle(.inset)
        }
    }
}

private struct ActionTag: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.2)))
            .foregroundStyle(color)
    }
    private var color: Color {
        switch text {
        case "commit", "commit (initial)", "commit (amend)": return .blue
        case "checkout", "switch": return .green
        case "merge": return .purple
        case "reset": return .orange
        case "rebase", "rebase (finish)", "rebase (start)": return .pink
        default: return .secondary
        }
    }
}
