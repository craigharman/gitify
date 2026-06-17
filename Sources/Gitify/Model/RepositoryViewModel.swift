import Foundation
import GitKit

/// Loads and holds the live data for one repository: status, refs, history, worktrees,
/// stashes. Created when a repository is selected; refreshed on demand.
@MainActor
@Observable
final class RepositoryViewModel {
    let ref: RepositoryRef

    private(set) var status: WorkingTreeStatus?
    private(set) var refs: [Ref] = []
    private(set) var commits: [Commit] = [] { didSet { graph = GraphLayout.layout(commits) } }
    private(set) var graph: CommitGraph = .empty
    private(set) var worktrees: [Worktree] = []
    private(set) var stashes: [Stash] = []
    private(set) var remotes: [GitRemote] = []
    private(set) var reflog: [ReflogEntry] = []
    /// An interrupted merge/rebase in progress, if any.
    private(set) var operation: RepositoryOperation?

    private(set) var isLoading = false
    private(set) var loadError: String?

    // Long-running network operation state (fetch/pull/push/clone).
    private(set) var operationTitle: String?
    private(set) var operationProgress: String?
    var isBusy: Bool { operationTitle != nil }

    // Working-tree / staging state.
    var selectedPath: String?
    private(set) var selectedStaged = false
    private(set) var currentDiff: FileDiff?
    var commitMessage: String = ""
    var amendMode: Bool = false
    private(set) var isCommitting = false

    private var service: CLIGitService?
    private var nextSkip: Int? = 0
    private var watcher: RepositoryWatcher?
    private var autoRefreshTask: Task<Void, Never>?

    init(ref: RepositoryRef) {
        self.ref = ref
    }
    // Cleanup is automatic: releasing `watcher` invalidates the FSEvents stream via its
    // own deinit, and the debounced refresh task holds only a weak self.

    var localBranches: [Ref] { refs.filter { $0.kind == .localBranch } }
    var remoteBranches: [Ref] { refs.filter { $0.kind == .remoteBranch } }
    var tags: [Ref] { refs.filter { $0.kind == .tag } }
    var currentBranch: Ref? { refs.first { $0.isHead } }

    /// Loads everything for first display.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let service = try await resolveService()
            async let status = service.status()
            async let refs = service.refs()
            async let worktrees = service.worktrees()
            async let stashes = service.stashes()
            async let firstPage = service.log(skip: 0, limit: 150)

            async let remotes = service.remotes()
            async let reflog = service.reflog(limit: 200)

            self.status = try await status
            self.refs = try await refs
            self.worktrees = try await worktrees
            self.stashes = try await stashes
            self.remotes = (try? await remotes) ?? []
            self.reflog = (try? await reflog) ?? []
            self.operation = await service.currentOperation()
            let page = try await firstPage
            self.commits = page.commits
            self.nextSkip = page.nextSkip
        } catch {
            loadError = "\(error)"
        }
    }

    /// Refreshes only the working-tree status and refs (cheap; after staging/commit).
    func refreshStatus() async {
        guard let service else { return }
        status = try? await service.status()
        refs = (try? await service.refs()) ?? refs
    }

    /// Loads the next page of history, appending to `commits`.
    func loadMoreHistory() async {
        guard let service, let skip = nextSkip, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if let page = try? await service.log(skip: skip, limit: 150) {
            commits.append(contentsOf: page.commits)
            nextSkip = page.nextSkip
        }
    }

    var canLoadMoreHistory: Bool { nextSkip != nil }

    // MARK: - Staging & diff

    /// Selects a file and loads its diff into `currentDiff`.
    func select(_ file: FileStatus, staged: Bool) async {
        selectedPath = file.path
        selectedStaged = staged
        await loadDiff(path: file.path, staged: staged)
    }

    private func loadDiff(path: String, staged: Bool) async {
        guard let service else { return }
        currentDiff = (try? await service.diff(path: path, staged: staged)) ?? .empty(path: path)
    }

    /// Stages or unstages a single hunk of the currently-displayed diff. The direction is
    /// inferred from whether the selected file is shown from the staged or unstaged side.
    func applyHunk(_ hunk: DiffHunk) async {
        guard let diff = currentDiff else { return }
        await mutate { try await $0.applyHunk(fileHeader: diff.header, hunkText: hunk.rawText,
                                              reverse: self.selectedStaged) }
    }

    func stage(_ file: FileStatus) async { await mutate { try await $0.stage(paths: [file.path]) } }
    func unstage(_ file: FileStatus) async { await mutate { try await $0.unstage(paths: [file.path]) } }
    func stageAll() async { await mutate { try await $0.stageAll() } }

    func discard(_ file: FileStatus) async {
        await mutate { try await $0.discard(paths: [file.path]) }
    }

    var canCommit: Bool {
        !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isCommitting
            && (amendMode || (status?.stagedFiles.isEmpty == false))
    }

    func commit() async {
        guard let service, canCommit else { return }
        isCommitting = true
        defer { isCommitting = false }
        do {
            try await service.commit(message: commitMessage, amend: amendMode)
            commitMessage = ""
            amendMode = false
            await reloadAfterMutation()
        } catch {
            loadError = "\(error)"
        }
    }

    /// Pre-fills the commit box with the last commit's message for amending.
    func prepareAmend() async {
        guard let service else { return }
        amendMode = true
        if commitMessage.isEmpty {
            commitMessage = (try? await service.lastCommitMessage()) ?? ""
        }
    }

    /// Runs a mutation, then refreshes status and the visible diff.
    private func mutate(_ action: (CLIGitService) async throws -> Void) async {
        guard let service else { return }
        do {
            try await action(service)
            await reloadAfterMutation()
        } catch {
            loadError = "\(error)"
        }
    }

    private func reloadAfterMutation() async {
        await refreshStatus()
        // Re-resolve the current selection against the refreshed status.
        if let path = selectedPath {
            let stillPresent = status?.files.contains { $0.path == path } ?? false
            if stillPresent {
                await loadDiff(path: path, staged: selectedStaged)
            } else {
                selectedPath = nil
                currentDiff = nil
            }
        }
        // Refresh history so amend/commit changes are reflected.
        if let page = try? await service?.log(skip: 0, limit: 150) {
            commits = page.commits
            nextSkip = page.nextSkip
        }
    }

    private func resolveService() async throws -> CLIGitService {
        if let service { return service }
        let service = try await CLIGitService(directory: ref.url)
        self.service = service
        startWatching(root: service.root)
        return service
    }

    // MARK: - Filesystem auto-refresh

    /// Begins watching the repository so external changes (editor saves, terminal git
    /// commands) refresh the UI automatically.
    private func startWatching(root: URL) {
        guard watcher == nil else { return }
        let watcher = RepositoryWatcher(root: root) { [weak self] in
            Task { @MainActor in self?.scheduleAutoRefresh() }
        }
        watcher.start()
        self.watcher = watcher
    }

    /// Debounces filesystem events into a single reload, skipping while a load or network
    /// operation is already in flight.
    private func scheduleAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, !self.isLoading, !self.isBusy else { return }
            await self.reloadEverything()
        }
    }

    // MARK: - Branch / tag / stash / worktree actions

    /// Runs a local mutation then reloads all repository data.
    private func perform(_ action: (CLIGitService) async throws -> Void) async {
        guard let service else { return }
        do {
            try await action(service)
            await reloadEverything()
        } catch {
            loadError = "\(error)"
        }
    }

    func checkout(_ revision: String) async { await perform { try await $0.checkout(revision) } }
    func createBranch(name: String, checkout: Bool) async {
        await perform { try await $0.createBranch(name: name, startPoint: nil, checkout: checkout) }
    }
    func deleteBranch(_ ref: Ref) async { await perform { try await $0.deleteBranch(name: ref.name, force: false) } }
    func forceDeleteBranch(_ ref: Ref) async { await perform { try await $0.deleteBranch(name: ref.name, force: true) } }
    func renameBranch(_ ref: Ref, to newName: String) async {
        await perform { try await $0.renameBranch(from: ref.name, to: newName) }
    }
    func createTag(name: String, on revision: String?, message: String?) async {
        await perform { try await $0.createTag(name: name, target: revision, message: message) }
    }
    func deleteTag(_ ref: Ref) async { await perform { try await $0.deleteTag(name: ref.name) } }

    func stashChanges(message: String?) async {
        await perform { try await $0.stashPush(message: message, includeUntracked: true) }
    }
    func applyStash(_ stash: Stash) async { await perform { try await $0.stashApply(stash.id) } }
    func popStash(_ stash: Stash) async { await perform { try await $0.stashPop(stash.id) } }
    func dropStash(_ stash: Stash) async { await perform { try await $0.stashDrop(stash.id) } }

    func addWorktree(path: String, branch: String?, create: Bool) async {
        await perform { try await $0.addWorktree(path: path, branch: branch, createBranch: create) }
    }
    func removeWorktree(_ worktree: Worktree) async {
        await perform { try await $0.removeWorktree(path: worktree.path, force: false) }
    }

    // MARK: - Network actions (with progress)

    func fetch() async {
        await runOperation("Fetching") { service, progress in
            try await service.fetch(remote: nil, onProgress: progress)
        }
    }
    func pull() async {
        await runOperation("Pulling") { service, progress in
            try await service.pull(onProgress: progress)
        }
    }
    func push() async {
        let setUpstream = currentBranch?.upstream == nil
        await runOperation("Pushing") { service, progress in
            try await service.push(remote: nil, branch: nil, setUpstream: setUpstream, onProgress: progress)
        }
    }

    // MARK: - Merge & rebase

    func mergePreview(branch: String) async -> MergePreview? {
        guard let service else { return nil }
        return try? await service.mergePreview(branch: branch)
    }

    func merge(branch: String, squash: Bool, noFastForward: Bool, noCommit: Bool, skipHooks: Bool) async {
        await runIntegration("Merge") {
            try await $0.merge(branch: branch, squash: squash, noFastForward: noFastForward,
                               noCommit: noCommit, skipHooks: skipHooks)
        }
    }

    func rebase(onto branch: String) async {
        await runIntegration("Rebase") { try await $0.rebase(onto: branch) }
    }

    func abortOperation() async {
        guard let op = operation else { return }
        await runIntegration("Abort") {
            switch op {
            case .merge: try await $0.abortMerge()
            case .rebase: try await $0.abortRebase()
            }
        }
    }

    /// Runs a merge/rebase/abort, then always reloads so an interrupted (conflicted) state
    /// is reflected even when the command exits non-zero.
    private func runIntegration(_ label: String, _ action: (CLIGitService) async throws -> Void) async {
        guard let service else { return }
        do {
            try await action(service)
        } catch {
            loadError = "\(label) stopped — resolve conflicts in the working tree, then commit. (\(error))"
        }
        await reloadEverything()
    }

    /// Runs a streamed network operation, surfacing live progress, then reloads.
    private func runOperation(
        _ title: String,
        _ action: (CLIGitService, @escaping @Sendable (String) -> Void) async throws -> Void
    ) async {
        guard let service, !isBusy else { return }
        operationTitle = title
        operationProgress = nil
        defer { operationTitle = nil; operationProgress = nil }

        let progress: @Sendable (String) -> Void = { [weak self] line in
            Task { @MainActor in self?.operationProgress = line }
        }
        do {
            try await action(service, progress)
            await reloadEverything()
        } catch {
            loadError = "\(error)"
        }
    }

    /// Reloads status, refs, history, worktrees, stashes, remotes, and reflog.
    private func reloadEverything() async {
        guard let service else { return }
        status = try? await service.status()
        refs = (try? await service.refs()) ?? refs
        worktrees = (try? await service.worktrees()) ?? worktrees
        stashes = (try? await service.stashes()) ?? stashes
        remotes = (try? await service.remotes()) ?? remotes
        reflog = (try? await service.reflog(limit: 200)) ?? reflog
        operation = await service.currentOperation()
        if let page = try? await service.log(skip: 0, limit: 150) {
            commits = page.commits
            nextSkip = page.nextSkip
        }
        if let path = selectedPath, status?.files.contains(where: { $0.path == path }) == true {
            await loadDiff(path: path, staged: selectedStaged)
        } else {
            selectedPath = nil
            currentDiff = nil
        }
    }
}
