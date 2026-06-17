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

    /// Files changed by a commit, with per-file line counts (for the history inspector).
    func commitChanges(sha: String) async throws -> [FileChange]

    /// The diff a commit applied to a single path.
    func commitFileDiff(sha: String, path: String) async throws -> FileDiff

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

    /// Creates a new branch from a stash and applies it (`git stash branch`).
    func stashBranch(name: String, selector: String) async throws

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

    /// Pulls the current branch from its upstream, optionally rebasing instead of merging.
    func pull(rebase: Bool, onProgress: (@Sendable (String) -> Void)?) async throws

    /// Pushes `branch` (default current) to `remote`. `force` uses `--force-with-lease`.
    func push(remote: String?, branch: String?, setUpstream: Bool, force: Bool,
              onProgress: (@Sendable (String) -> Void)?) async throws

    /// Pushes all tags to `remote`.
    func pushTags(remote: String?, onProgress: (@Sendable (String) -> Void)?) async throws

    /// Deletes `branch` on `remote` (`git push <remote> --delete`).
    func deleteRemoteBranch(remote: String, branch: String,
                            onProgress: (@Sendable (String) -> Void)?) async throws

    /// Adds a new remote.
    func addRemote(name: String, url: String) async throws

    /// Removes a remote.
    func removeRemote(name: String) async throws

    // MARK: Merge & rebase

    /// Dry-run merge of `branch` into HEAD, reporting any conflicting files.
    func mergePreview(branch: String) async throws -> MergePreview

    /// Merges `branch` into the current HEAD.
    /// - squash: combine changes into the index without committing (`--squash`).
    /// - noFastForward: always create a merge commit (`--no-ff`).
    /// - noCommit: perform the merge but stop before committing (`--no-commit`).
    /// - skipHooks: bypass pre-merge / commit-msg hooks (`--no-verify`).
    func merge(branch: String, squash: Bool, noFastForward: Bool,
               noCommit: Bool, skipHooks: Bool) async throws

    /// Rebases the current HEAD onto `branch`.
    func rebase(onto branch: String) async throws

    /// Applies `sha` as a new commit on the current branch (`git cherry-pick`).
    func cherryPick(sha: String) async throws

    /// Creates a commit that undoes `sha` (`git revert --no-edit`).
    func revert(sha: String) async throws

    /// Moves the current branch to `sha`. `mode` controls index/working-tree handling.
    func reset(to sha: String, mode: ResetMode) async throws

    /// Aborts an in-progress merge.
    func abortMerge() async throws

    /// Aborts an in-progress rebase.
    func abortRebase() async throws

    /// The interrupted operation currently in progress, if any.
    func currentOperation() async -> RepositoryOperation?

    // MARK: Repository stats (best-effort)

    /// Lines-of-code per language across tracked text files.
    func languageStats() async -> [LanguageStat]

    /// Top contributors by commit count (`git shortlog`).
    func topCommitters(limit: Int) async -> [Committer]

    /// The repository's README contents, if one exists at the root.
    func readme() async -> String?

    // MARK: Config & conflicts

    /// The effective value of a git config key (local, falling back to global).
    func configValue(_ key: String) async -> String?

    /// Sets a git config value, locally or `--global`.
    func setConfigValue(_ key: String, _ value: String, global: Bool) async throws

    /// Files with unresolved merge conflicts.
    func conflictedFiles() async throws -> [String]

    /// Resolves a conflicted file by taking our side (`useOurs`) or theirs, then staging it.
    func resolveConflict(path: String, useOurs: Bool) async throws
}

public extension GitService {
    func log(skip: Int = 0, limit: Int = 200, revisions: [String] = ["--all"]) async throws -> CommitPage {
        try await log(skip: skip, limit: limit, revisions: revisions)
    }
}
