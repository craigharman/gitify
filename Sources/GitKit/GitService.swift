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

    /// Stages (reverse == false) or unstages (reverse == true) a single hunk by applying
    /// `fileHeader` + `hunkText` as a patch to the index.
    func applyHunk(fileHeader: String, hunkText: String, reverse: Bool) async throws

    /// Creates a commit with `message`. When `amend` is true, rewrites the last commit.
    func commit(message: String, amend: Bool) async throws

    /// The message of the most recent commit (for pre-filling an amend).
    func lastCommitMessage() async throws -> String

    // MARK: Remotes & reflog

    /// Configured remotes.
    func remotes() async throws -> [GitRemote]

    /// Recent reflog entries (HEAD), newest first.
    func reflog(limit: Int) async throws -> [ReflogEntry]

    // MARK: Branches & tags

    /// Checks out an existing branch, tag, or commit.
    func checkout(_ revision: String) async throws

    /// Creates a branch at `startPoint` (default HEAD), optionally checking it out.
    func createBranch(name: String, startPoint: String?, checkout: Bool) async throws

    /// Deletes a local branch (`-d`, or `-D` when `force`).
    func deleteBranch(name: String, force: Bool) async throws

    /// Renames a local branch.
    func renameBranch(from oldName: String, to newName: String) async throws

    /// Creates a tag (annotated when `message` is non-nil) at `target` (default HEAD).
    func createTag(name: String, target: String?, message: String?) async throws

    /// Deletes a tag.
    func deleteTag(name: String) async throws

    // MARK: Stashes

    /// Stashes working-tree changes.
    func stashPush(message: String?, includeUntracked: Bool) async throws

    /// Applies a stash without removing it.
    func stashApply(_ selector: String) async throws

    /// Applies a stash and removes it.
    func stashPop(_ selector: String) async throws

    /// Drops a stash.
    func stashDrop(_ selector: String) async throws

    // MARK: Worktrees

    /// Adds a worktree at `path`, optionally checking out / creating `branch`.
    func addWorktree(path: String, branch: String?, createBranch: Bool) async throws

    /// Removes a worktree (`--force` when `force`).
    func removeWorktree(path: String, force: Bool) async throws

    /// Prunes stale worktree administrative entries.
    func pruneWorktrees() async throws

    // MARK: Network (streamed progress)

    /// Fetches from a remote (all remotes when `remote` is nil), pruning deleted refs.
    func fetch(remote: String?, onProgress: (@Sendable (String) -> Void)?) async throws

    /// Pulls the current branch from its upstream.
    func pull(onProgress: (@Sendable (String) -> Void)?) async throws

    /// Pushes `branch` (default current) to `remote`, optionally setting upstream.
    func push(remote: String?, branch: String?, setUpstream: Bool,
              onProgress: (@Sendable (String) -> Void)?) async throws
}

public extension GitService {
    func log(skip: Int = 0, limit: Int = 200, revisions: [String] = ["--all"]) async throws -> CommitPage {
        try await log(skip: skip, limit: limit, revisions: revisions)
    }
}
