import SwiftUI
import GitKit

/// Repository overview (Screenshot 1): location, status summary, branches/remotes counts.
struct OverviewView: View {
    let viewModel: RepositoryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(viewModel.ref.name)
                    .font(.largeTitle.bold())

                infoSection
                statsSection
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var infoSection: some View {
        GroupBox("Info") {
            VStack(spacing: 0) {
                row("Location", viewModel.ref.path, systemImage: "folder")
                Divider()
                row("Status",
                    viewModel.status.map { $0.hasChanges ? "\($0.files.count) files changed" : "Clean working tree" } ?? "—",
                    systemImage: "circle.fill")
                if let branch = viewModel.currentBranch {
                    Divider()
                    row("Current Branch", branch.name, systemImage: "arrow.triangle.branch")
                }
            }
        }
    }

    private var statsSection: some View {
        GroupBox("Refs") {
            VStack(spacing: 0) {
                row("Local Branches", "\(viewModel.localBranches.count)", systemImage: "arrow.triangle.branch")
                Divider()
                row("Remote Branches", "\(viewModel.remoteBranches.count)", systemImage: "cloud")
                Divider()
                row("Tags", "\(viewModel.tags.count)", systemImage: "tag")
                Divider()
                row("Worktrees", "\(viewModel.worktrees.count)", systemImage: "square.split.2x1")
                Divider()
                row("Stashes", "\(viewModel.stashes.count)", systemImage: "tray.full")
            }
        }
    }

    private func row(_ title: String, _ value: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 8)
    }
}
