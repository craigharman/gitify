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
    private(set) var commits: [Commit] = []
    private(set) var worktrees: [Worktree] = []
    private(set) var stashes: [Stash] = []

    private(set) var isLoading = false
    private(set) var loadError: String?

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

    private func resolveService() async throws -> CLIGitService {
        if let service { return service }
        let service = try await CLIGitService(directory: ref.url)
        self.service = service
        return service
    }
}
