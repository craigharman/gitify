import SwiftUI
import GitKit

/// Merge dialog (Gitfox-style): pick a branch, preview conflicts, choose options.
struct MergeSheet: View {
    let viewModel: RepositoryViewModel
    /// Branch whose changes are merged in (editable via the picker).
    @State var source: String
    /// Branch the merge lands on. Checked out first if it isn't already current.
    let target: String
    @Environment(\.dismiss) private var dismiss

    @State private var squash = false
    @State private var noFastForward = false
    @State private var noCommit = false
    @State private var skipHooks = false
    @State private var deleteSource = false
    @State private var preview: MergePreview?
    @State private var loadingPreview = false

    /// Any branch except the target is a valid source (you can't merge a branch into itself).
    private var branches: [String] {
        (viewModel.localBranches.map(\.name) + viewModel.remoteBranches.map(\.name))
            .filter { $0 != target }
    }
    /// True when `target` is already checked out, so the conflict preview (computed against
    /// HEAD) is meaningful and no branch switch is needed.
    private var mergesIntoCurrent: Bool { viewModel.currentBranch?.name == target }
    private var sourceIsLocal: Bool { viewModel.localBranches.contains { $0.name == source } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SheetHeader(symbol: "arrow.triangle.merge", title: "Merge",
                        subtitle: "Merge changes from “\(source)” into “\(target)”.")

            LabeledRow("From") {
                Picker("", selection: $source) {
                    ForEach(branches, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
            }
            LabeledRow("Into") {
                HStack(spacing: 6) {
                    Text(target)
                    if !mergesIntoCurrent {
                        Text("(will be checked out)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            LabeledRow("Conflicts") { conflictStatus }

            VStack(alignment: .leading, spacing: 10) {
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
                if sourceIsLocal {
                    option("Delete “\(source)” After Merge",
                           "Removes the local branch once it has been merged in.",
                           isOn: $deleteSource, disabled: noCommit)
                }
            }
            .padding(.leading, FormMetrics.contentInset) // align checkboxes under the fields

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Merge") {
                    Task {
                        await viewModel.merge(source: source, into: target, squash: squash,
                                              noFastForward: noFastForward, noCommit: noCommit,
                                              skipHooks: skipHooks,
                                              deleteSource: deleteSource && sourceIsLocal)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(source.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 600, height: 480)
        .task(id: source) { await loadPreview() }
    }

    @ViewBuilder
    private var conflictStatus: some View {
        if !mergesIntoCurrent {
            // The preview is computed against HEAD; it isn't meaningful when the merge will
            // first switch to a different target branch.
            Text("Checked after switching to “\(target)”.").foregroundStyle(.secondary)
        } else if loadingPreview {
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking…").foregroundStyle(.secondary) }
        } else if let preview {
            HStack(spacing: 6) {
                Image(systemName: preview.isClean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(preview.isClean ? .green : .orange)
                Text("Branch “\(source)” has \(preview.conflictCount) conflict\(preview.conflictCount == 1 ? "" : "s") with “\(target)”")
            }
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    private func loadPreview() async {
        guard mergesIntoCurrent else { preview = nil; return }
        loadingPreview = true
        defer { loadingPreview = false }
        preview = await viewModel.mergePreview(branch: source)
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
        HStack(alignment: .firstTextBaseline, spacing: FormMetrics.labelGap) {
            Text("\(label):")
                .frame(width: FormMetrics.labelWidth, alignment: .trailing)
                .foregroundStyle(.secondary)
            content
        }
    }
}

/// Shared metrics so labeled fields and the option checkboxes line up on one content column.
private enum FormMetrics {
    static let labelWidth: CGFloat = 80
    static let labelGap: CGFloat = 8
    /// Left inset of the content column (right edge of the label gutter).
    static var contentInset: CGFloat { labelWidth + labelGap }
}
