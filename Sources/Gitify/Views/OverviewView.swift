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
                if !viewModel.languageStats.isEmpty { languageSection }
                if !viewModel.topCommitters.isEmpty { committersSection }
                readmeSection
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await viewModel.loadStatsIfNeeded() }
    }

    private var languageSection: some View {
        let total = max(viewModel.languageStats.reduce(0) { $0 + $1.lines }, 1)
        return GroupBox("Line Count") {
            VStack(spacing: 8) {
                ForEach(Array(viewModel.languageStats.prefix(8).enumerated()), id: \.element.id) { index, stat in
                    HStack(spacing: 10) {
                        Text(stat.language).frame(width: 120, alignment: .leading)
                        GeometryReader { geo in
                            Capsule()
                                .fill(GraphMetrics.color(index))
                                .frame(width: max(6, geo.size.width * CGFloat(stat.lines) / CGFloat(total)))
                        }
                        .frame(height: 14)
                        Text("\(stat.lines)").font(.callout.monospacedDigit())
                            .frame(width: 70, alignment: .trailing).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var committersSection: some View {
        GroupBox("Top Committers") {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.topCommitters.enumerated()), id: \.element.id) { index, committer in
                    if index > 0 { Divider() }
                    HStack(spacing: 10) {
                        AvatarView(name: committer.name)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(committer.name)
                            if !committer.email.isEmpty {
                                Text(committer.email).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(committer.commits)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    @ViewBuilder
    private var readmeSection: some View {
        GroupBox("README") {
            Group {
                if let readme = viewModel.readme, !readme.isEmpty {
                    MarkdownView(markdown: readme)
                } else {
                    Text("No README").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
