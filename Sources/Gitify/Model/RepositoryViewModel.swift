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

    private(set) var isLoading = false
    private(set) var loadError: String?

    // Working-tree / staging state.
    var selectedPath: String?
    private(set) var selectedStaged = false
    private(set) var currentDiff: FileDiff?
    var commitMessage: String = ""
    var amendMode: Bool = false
    private(set) var isCommitting = false

    private var service: CLIGitService?
    private var nextSkip: Int? = 0

    init(ref: RepositoryRef) {
        self.ref = ref
    }

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

            self.status = try await status
            self.refs = try await refs
            self.worktrees = try await worktrees
            self.stashes = try await stashes
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
        return service
    }
}
