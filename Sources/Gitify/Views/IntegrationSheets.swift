import SwiftUI
import GitKit

/// Merge dialog (Gitfox-style): pick a branch, preview conflicts, choose options.
struct MergeSheet: View {
    let viewModel: RepositoryViewModel
    @State var branch: String
    @Environment(\.dismiss) private var dismiss

    @State private var squash = false
    @State private var noFastForward = false
    @State private var noCommit = false
    @State private var skipHooks = false
    @State private var preview: MergePreview?
    @State private var loadingPreview = false

    private var branches: [String] {
        viewModel.localBranches.filter { !$0.isHead }.map(\.name) + viewModel.remoteBranches.map(\.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(symbol: "arrow.triangle.merge", title: "Merge",
                        subtitle: "Merge changes from the selected branch into the current HEAD.")

            LabeledRow("Branch") {
                Picker("", selection: $branch) {
                    ForEach(branches, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }

            LabeledRow("Conflicts") { conflictStatus }

            VStack(alignment: .leading, spacing: 12) {
                option("Squash Commits", "Combine all changes into one single commit.",
                       isOn: $squash)
                option("Always Generate Merge Commit",
                       "Always generate a merge commit, even if the merge can be fast-forwarded.",
                       isOn: $noFastForward, disabled: squash)
                option("No Automatic Commit",
                       "Perform the merge and stop just before creating a merge commit.",
                       isOn: $noCommit, disabled: squash, indent: true)
                option("Skip Hooks", "Skip the pre-merge and commit message hooks.",
                       isOn: $skipHooks)
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Merge") {
                    Task {
                        await viewModel.merge(branch: branch, squash: squash, noFastForward: noFastForward,
                                              noCommit: noCommit, skipHooks: skipHooks)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(branch.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560, height: 460)
        .task(id: branch) { await loadPreview() }
    }

    @ViewBuilder
    private var conflictStatus: some View {
        if loadingPreview {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
        } else if let preview {
            HStack(spacing: 6) {
                Image(systemName: preview.isClean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(preview.isClean ? .green : .orange)
                Text("Branch “\(branch)” has \(preview.conflictCount) conflict\(preview.conflictCount == 1 ? "" : "s") with HEAD")
            }
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    private func loadPreview() async {
        loadingPreview = true
        defer { loadingPreview = false }
        preview = await viewModel.mergePreview(branch: branch)
    }

    private func option(_ title: String, _ detail: String, isOn: Binding<Bool>,
                        disabled: Bool = false, indent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: isOn).disabled(disabled)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.leading, indent ? 20 : 0)
        .opacity(disabled ? 0.5 : 1)
    }
}

/// Rebase dialog: pick a branch to rebase the current HEAD onto.
struct RebaseSheet: View {
    let viewModel: RepositoryViewModel
    @State var branch: String
    @Environment(\.dismiss) private var dismiss

    private var branches: [String] {
        viewModel.localBranches.filter { !$0.isHead }.map(\.name) + viewModel.remoteBranches.map(\.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(symbol: "arrow.uturn.up", title: "Rebase",
                        subtitle: "Rebase the current HEAD on the selected branch.")

            LabeledRow("Branch") {
                Picker("", selection: $branch) {
                    ForEach(branches, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Rebase") {
                    Task { await viewModel.rebase(onto: branch); dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(branch.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560, height: 220)
    }
}

private struct SheetHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
        }
    }
}

private struct LabeledRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(label):").frame(width: 80, alignment: .trailing).foregroundStyle(.secondary)
            content
        }
    }
}
