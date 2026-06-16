import Foundation

/// A page of commits loaded from history.
public struct CommitPage: Sendable {
    public let commits: [Commit]
    /// Offset to pass as `skip` for the next page; nil when history is exhausted.
    public let nextSkip: Int?

    public init(commits: [Commit], nextSkip: Int?) {
        self.commits = commits
        self.nextSkip = nextSkip
    }
}

/// All read operations Gitify needs from a repository. Implemented by `CLIGitService`
/// today; the protocol keeps the door open to a libgit2-backed fast path later.
public protocol GitService: Sendable {
    /// Absolute path to the repository's top-level working directory.
    var root: URL { get }

    /// Current working-tree status (staged + unstaged + untracked).
    func status() async throws -> WorkingTreeStatus

    /// A page of history starting `skip` commits back, up to `limit` commits.
    /// `revisions` defaults to `--all` so the graph spans every ref.
    func log(skip: Int, limit: Int, revisions: [String]) async throws -> CommitPage

    /// Local branches, remote branches, and tags.
    func refs() async throws -> [Ref]

    /// All worktrees, including the main one.
    func worktrees() async throws -> [Worktree]

    /// The stash stack, newest first.
    func stashes() async throws -> [Stash]

    // MARK: Diffs

    /// The diff for a single path. `staged` selects the index-vs-HEAD diff; otherwise the
    /// working-tree-vs-index diff. Untracked files are rendered as all-additions.
    func diff(path: String, staged: Bool) async throws -> FileDiff

    // MARK: Mutations

    /// Stages the given paths (`git add`).
    func stage(paths: [String]) async throws

    /// Stages every change in the working tree (`git add -A`).
    func stageAll() async throws

    /// Unstages the given paths (`git restore --staged`).
    func unstage(paths: [String]) async throws

    /// Discards working-tree changes for the given paths. Destructive — deletes untracked
    /// files and reverts tracked ones.
    func discard(paths: [String]) async throws

    /// Creates a commit with `message`. When `amend` is true, rewrites the last commit.
    func commit(message: String, amend: Bool) async throws

    /// The message of the most recent commit (for pre-filling an amend).
    func lastCommitMessage() async throws -> String
}

public extension GitService {
    func log(skip: Int = 0, limit: Int = 200, revisions: [String] = ["--all"]) async throws -> CommitPage {
        try await log(skip: skip, limit: limit, revisions: revisions)
    }
}
