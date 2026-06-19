import AppKit
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
    private(set) var submodules: [Submodule] = []
    /// An interrupted merge/rebase in progress, if any.
    private(set) var operation: RepositoryOperation?

    // Overview stats (loaded lazily when the Overview is shown).
    private(set) var languageStats: [LanguageStat] = []
    private(set) var topCommitters: [Committer] = []
    private(set) var readme: String?
    private var statsLoaded = false

    private(set) var isLoading = false
    private(set) var loadError: String?

    /// Clears the current error banner (the user dismissed it).
    func dismissError() { loadError = nil }

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

    /// Source branch a "delete on merge" request wants removed, remembered while a merge is
    /// being completed. A conflicting merge can't delete immediately (it's finished later by a
    /// manual commit), so the intent is parked here until the merge is actually committed.
    private var pendingMergeSourceToDelete: String?

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
            self.submodules = await service.submodules()
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

    /// Stages/unstages only the selected lines of a hunk (indices into `hunk.lines`).
    func applyLines(_ hunk: DiffHunk, _ selected: Set<Int>) async {
        guard let diff = currentDiff, !selected.isEmpty else { return }
        await mutate { try await $0.applyHunkLines(fileHeader: diff.header, hunk: hunk,
                                                   selected: selected, reverse: self.selectedStaged) }
    }

    func stage(_ file: FileStatus) async { await mutate { try await $0.stage(paths: [file.path]) } }
    func unstage(_ file: FileStatus) async { await mutate { try await $0.unstage(paths: [file.path]) } }
    func stageAll() async { await mutate { try await $0.stageAll() } }

    func discard(_ file: FileStatus) async {
        await mutate { try await $0.discard(paths: [file.path]) }
    }

    func discardFiles(_ files: [FileStatus]) async {
        guard !files.isEmpty else { return }
        await mutate { try await $0.discard(paths: files.map(\.path)) }
    }

    func deleteFiles(_ files: [FileStatus]) async {
        guard !files.isEmpty else { return }
        for file in files {
            let url = ref.url.appendingPathComponent(file.path)
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
        await reloadAfterMutation()
    }

    func ignoreFiles(_ files: [FileStatus]) async {
        guard let service, !files.isEmpty else { return }
        do {
            try service.addToGitignore(patterns: files.map(\.path))
            await reloadAfterMutation()
        } catch {
            loadError = "\(error)"
        }
    }

    func untrackFiles(_ files: [FileStatus]) async {
        guard !files.isEmpty else { return }
        await mutate { try await $0.untrack(paths: files.map(\.path)) }
    }

    func revealInFinder(_ files: [FileStatus]) {
        let urls = files.map { ref.url.appendingPathComponent($0.path) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func openInDefaultEditor(_ files: [FileStatus]) {
        let urls = files.map { ref.url.appendingPathComponent($0.path) }
        if let bundleID = AppDefaults.editorBundleID,
           let appURL = AppDefaults.appURL(for: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config)
        } else {
            for url in urls { NSWorkspace.shared.open(url) }
        }
    }

    func openInTerminal(_ file: FileStatus) {
        let dir = ref.url.appendingPathComponent(file.path).deletingLastPathComponent()
        let bundleID = AppDefaults.terminalBundleID
        let appURL = AppDefaults.appURL(for: bundleID)
            ?? URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([dir], withApplicationAt: appURL, configuration: config)
    }

    func stageFiles(_ files: [FileStatus]) async {
        guard !files.isEmpty else { return }
        await mutate { try await $0.stage(paths: files.map(\.path)) }
    }

    func unstageFiles(_ files: [FileStatus]) async {
        guard !files.isEmpty else { return }
        await mutate { try await $0.unstage(paths: files.map(\.path)) }
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
            // A commit while a "delete on merge" is parked is the manual completion of a
            // conflicted merge — finalize the deletion now, then reload refs so the gone
            // branch disappears (reloadAfterMutation refreshes status/history only).
            if pendingMergeSourceToDelete != nil {
                await finalizePendingMergeDeletion()
                await reloadEverything()
            } else {
                await reloadAfterMutation()
            }
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
    func branchFromStash(_ stash: Stash, name: String) async {
        await perform { try await $0.stashBranch(name: name, selector: stash.id) }
    }

    // MARK: - Config & conflicts

    func configValue(_ key: String) async -> String? {
        guard let service else { return nil }
        return await service.configValue(key)
    }
    func setConfigValue(_ key: String, _ value: String, global: Bool) async {
        await perform { try await $0.setConfigValue(key, value, global: global) }
    }
    func resolveConflict(_ file: FileStatus, useOurs: Bool) async {
        await mutate { try await $0.resolveConflict(path: file.path, useOurs: useOurs) }
    }
    func markResolved(_ file: FileStatus) async { await stage(file) }
    func fileContents(_ path: String) async -> String? {
        guard let service else { return nil }
        return await service.fileContents(path: path)
    }
    func resolveFile(path: String, contents: String) async {
        await mutate { try await $0.resolveFile(path: path, contents: contents) }
    }

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
    func pull(rebase: Bool = false) async {
        await runOperation(rebase ? "Pulling (rebase)" : "Pulling") { service, progress in
            try await service.pull(rebase: rebase, onProgress: progress)
        }
    }
    /// Pulls with an explicit merge (--no-rebase), useful when branches have diverged
    /// and the user wants to resolve via merge regardless of their git config.
    func pullMerge() async {
        await runOperation("Pulling (merge)") { service, progress in
            try await service.pull(rebase: false, noRebase: true, onProgress: progress)
        }
    }
    func push(force: Bool = false) async {
        let setUpstream = currentBranch?.upstream == nil
        await runOperation(force ? "Force Pushing" : "Pushing") { service, progress in
            try await service.push(remote: nil, branch: nil, setUpstream: setUpstream,
                                   force: force, onProgress: progress)
        }
    }
    /// Pushes a specific branch (by name) to its upstream remote.
    func pushBranch(_ name: String) async {
        guard let ref = refs.first(where: { $0.kind == .localBranch && $0.name == name }) else { return }
        let setUpstream = ref.upstream == nil

        let remote: String?
        if let upstream = ref.upstream, let slash = upstream.firstIndex(of: "/") {
            remote = String(upstream[..<slash])
        } else if let match = remoteBranches.first(where: { $0.name.hasSuffix("/\(name)") }),
                  let slash = match.name.firstIndex(of: "/") {
            remote = String(match.name[..<slash])
        } else {
            remote = remotes.first?.name
        }

        guard let remote else {
            loadError = "No remote configured for “\(name)”."
            return
        }

        await runOperation("Pushing \(name)") { service, progress in
            try await service.push(remote: remote, branch: name, setUpstream: setUpstream,
                                   force: false, onProgress: progress)
        }
    }
    func pushTags() async {
        await runOperation("Pushing Tags") { service, progress in
            try await service.pushTags(remote: nil, onProgress: progress)
        }
    }
    func deleteRemoteBranch(remote: String, branch: String) async {
        await runOperation("Deleting \(remote)/\(branch)") { service, progress in
            try await service.deleteRemoteBranch(remote: remote, branch: branch, onProgress: progress)
        }
    }
    func addRemote(name: String, url: String) async { await perform { try await $0.addRemote(name: name, url: url) } }
    func removeRemote(_ name: String) async { await perform { try await $0.removeRemote(name: name) } }
    func updateSubmodules(path: String?) async {
        await runOperation(path == nil ? "Updating Submodules" : "Updating Submodule") { service, progress in
            try await service.updateSubmodules(path: path)
        }
    }
    func addSubmodule(url: String, path: String) async {
        await runOperation("Adding Submodule") { service, progress in
            try await service.addSubmodule(url: url, path: path)
        }
    }

    // MARK: - Merge & rebase

    func mergePreview(branch: String) async -> MergePreview? {
        guard let service else { return nil }
        return try? await service.mergePreview(branch: branch)
    }

    // MARK: - Overview stats

    /// Loads language/committer/README stats once per repository state (invalidated on reload).
    func loadStatsIfNeeded() async {
        guard !statsLoaded, let service = try? await resolveService() else { return }
        statsLoaded = true
        async let languages = service.languageStats()
        async let committers = service.topCommitters(limit: 8)
        async let readme = service.readme()
        self.languageStats = await languages
        self.topCommitters = await committers
        self.readme = await readme
    }

    // MARK: - Commit inspection

    func commitChanges(_ sha: String) async -> [FileChange] {
        guard let service else { return [] }
        return (try? await service.commitChanges(sha: sha)) ?? []
    }

    func commitFileDiff(_ sha: String, path: String) async -> FileDiff? {
        guard let service else { return nil }
        return try? await service.commitFileDiff(sha: sha, path: path)
    }

    func merge(branch: String, squash: Bool, noFastForward: Bool, noCommit: Bool, skipHooks: Bool) async {
        await runIntegration("Merge") {
            try await $0.merge(branch: branch, squash: squash, noFastForward: noFastForward,
                               noCommit: noCommit, skipHooks: skipHooks)
        }
    }

    /// Merges `source` into `target`. When `target` isn't the current branch it is checked out
    /// first so the merge lands on it — letting you merge the branch you're on into another
    /// (e.g. a feature into main) without manually switching first. On a clean merge, optionally
    /// deletes the now-merged `source` branch.
    func merge(source: String, into target: String, squash: Bool, noFastForward: Bool,
               noCommit: Bool, skipHooks: Bool, deleteSource: Bool,
               pushAfterMerge: Bool = false) async {
        // Park the deletion intent before attempting the merge so it survives a conflict: a
        // conflicting merge throws below and is finished later by a manual commit, which calls
        // finalizePendingMergeDeletion(). Don't delete when stopping before commit — nothing
        // is merged yet.
        if deleteSource && !noCommit {
            pendingMergeSourceToDelete = source
        }
        await runIntegration("Merge") { service in
            if target != self.currentBranch?.name {
                try await service.checkout(target)
            }
            try await service.merge(branch: source, squash: squash, noFastForward: noFastForward,
                                    noCommit: noCommit, skipHooks: skipHooks)
            // Reaching here means the merge completed cleanly (a conflicting merge throws above).
            await self.finalizePendingMergeDeletion()
        }
        // If the merge didn't leave a conflicted merge in progress (it finalized cleanly above,
        // or failed for a non-conflict reason), drop any stale intent so it can't leak into a
        // later unrelated commit.
        if operation != .merge {
            pendingMergeSourceToDelete = nil
            if pushAfterMerge { await push() }
        }
    }

    /// Deletes the branch a "delete on merge" request targeted, once the merge has actually
    /// been committed. No-op when nothing is pending; a failed deletion surfaces a banner but
    /// doesn't undo the completed merge.
    private func finalizePendingMergeDeletion() async {
        guard let source = pendingMergeSourceToDelete, let service else { return }
        pendingMergeSourceToDelete = nil
        do {
            try await service.deleteBranch(name: source, force: false)
        } catch {
            loadError = "Merged, but couldn’t delete “\(source)”: \(error)"
        }
    }

    func rebase(onto branch: String) async {
        await runIntegration("Rebase") { try await $0.rebase(onto: branch) }
    }

    func cherryPick(_ sha: String) async { await runIntegration("Cherry-pick") { try await $0.cherryPick(sha: sha) } }
    func revert(_ sha: String) async { await runIntegration("Revert") { try await $0.revert(sha: sha) } }
    func reset(to sha: String, mode: ResetMode) async {
        await runIntegration("Reset") { try await $0.reset(to: sha, mode: mode) }
    }

    func abortOperation() async {
        guard let op = operation else { return }
        // Aborting a conflicted merge cancels any parked "delete on merge" request too.
        pendingMergeSourceToDelete = nil
        await runIntegration("Abort") {
            switch op {
            case .merge: try await $0.abortMerge()
            case .rebase: try await $0.abortRebase()
            }
        }
    }

    func continueRebase() async {
        await runIntegration("Rebase Continue") { try await $0.continueRebase() }
    }

    func skipRebase() async {
        await runIntegration("Rebase Skip") { try await $0.skipRebase() }
    }

    /// Runs a merge/rebase/abort, then always reloads so an interrupted (conflicted) state
    /// is reflected even when the command exits non-zero.
    private func runIntegration(_ label: String, _ action: (CLIGitService) async throws -> Void) async {
        guard let service else { return }
        do {
            try await action(service)
        } catch {
            let hint = label.lowercased().contains("rebase")
                ? "resolve conflicts and stage, then continue or skip"
                : "resolve conflicts in the working tree, then commit"
            loadError = "\(label) stopped \u{2014} \(hint). (\(error))"
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
        } catch {
            loadError = "\(error)"
        }
        await reloadEverything() // always reload (e.g. a pull --rebase may leave conflicts)
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
        submodules = await service.submodules()
        operation = await service.currentOperation()
        statsLoaded = false // recompute overview stats on next visit
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
