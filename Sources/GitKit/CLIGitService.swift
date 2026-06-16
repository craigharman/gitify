import Foundation

/// Field / record separators embedded literally in git format strings. Because we exec
/// `git` directly (no shell), literal control bytes in arguments pass through untouched,
/// so these are safe even though they appear nowhere in real ref names or messages.
private let unitSeparator = "\u{1f}"   // between fields
private let recordSeparator = "\u{1e}" // between records

/// `GitService` backed by the user's installed `git` binary.
public struct CLIGitService: GitService {
    public let root: URL
    private let runner: GitRunner

    /// Creates a service rooted at `directory`. Resolves to the repository top-level so
    /// that all paths are reported relative to a stable root.
    public init(directory: URL, executablePath: String? = nil) async throws {
        let probe = GitRunner(workingDirectory: directory, executablePath: executablePath)
        let result = try await probe.runRaw(["rev-parse", "--show-toplevel"])
        guard result.succeeded else {
            throw GitError.notARepository(directory.path)
        }
        let top = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        self.root = URL(fileURLWithPath: top)
        self.runner = GitRunner(workingDirectory: self.root, executablePath: executablePath)
    }

    /// Discovers the repository top-level for an arbitrary path, returning nil if none.
    public static func repositoryRoot(for directory: URL, executablePath: String? = nil) async -> URL? {
        let probe = GitRunner(workingDirectory: directory, executablePath: executablePath)
        guard let result = try? await probe.runRaw(["rev-parse", "--show-toplevel"]),
              result.succeeded else { return nil }
        let top = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return top.isEmpty ? nil : URL(fileURLWithPath: top)
    }

    // MARK: - Status

    public func status() async throws -> WorkingTreeStatus {
        let data = try await runner.run(["status", "--porcelain=v2", "--branch", "-z"])
        return StatusParser.parse(data)
    }

    // MARK: - Log

    public func log(skip: Int, limit: Int, revisions: [String]) async throws -> CommitPage {
        let format = [
            "%H", "%P", "%an", "%ae", "%aI",
            "%cn", "%ce", "%cI", "%s", "%b", "%D",
        ].joined(separator: unitSeparator) + recordSeparator

        // Request one extra commit to detect whether another page exists.
        var args = ["log", "--topo-order", "--pretty=format:\(format)",
                    "--skip=\(skip)", "-n", "\(limit + 1)"]
        args.append(contentsOf: revisions)

        let output = try await runner.runString(args)
        var commits = CommitParser.parse(output)

        let hasMore = commits.count > limit
        if hasMore { commits.removeLast(commits.count - limit) }
        return CommitPage(commits: commits, nextSkip: hasMore ? skip + limit : nil)
    }

    // MARK: - Refs

    public func refs() async throws -> [Ref] {
        let format = [
            "%(refname)", "%(objecttype)", "%(objectname)", "%(*objectname)",
            "%(HEAD)", "%(upstream:short)", "%(upstream:track)",
        ].joined(separator: unitSeparator)

        let output = try await runner.runString([
            "for-each-ref", "--format=\(format)",
            "refs/heads", "refs/remotes", "refs/tags",
        ])
        return RefParser.parse(output)
    }

    // MARK: - Worktrees

    public func worktrees() async throws -> [Worktree] {
        let output = try await runner.runString(["worktree", "list", "--porcelain"])
        return WorktreeParser.parse(output)
    }

    // MARK: - Stashes

    public func stashes() async throws -> [Stash] {
        let format = ["%gd", "%gs"].joined(separator: unitSeparator)
        let output = try await runner.runString(["stash", "list", "--format=\(format)"])
        return StashParser.parse(output)
    }

    // MARK: - Diffs

    public func diff(path: String, staged: Bool) async throws -> FileDiff {
        var args = ["diff", "--no-color", "--no-ext-diff", "-U3"]
        if staged { args.append("--cached") }
        args.append(contentsOf: ["--", path])
        let result = try await runner.runRaw(args)

        // A non-empty result means tracked changes; empty likely means an untracked file,
        // which `git diff` ignores. Fall back to diffing against an empty tree.
        if result.succeeded, !result.stdoutString.isEmpty {
            return DiffParser.parse(result.stdoutString, fallbackPath: path)
        }
        if !staged {
            return try await untrackedDiff(path: path)
        }
        return FileDiff.empty(path: path)
    }

    /// Renders an untracked file as additions using `git diff --no-index` against /dev/null.
    /// That command exits 1 when differences exist, so we tolerate exit codes 0 and 1.
    private func untrackedDiff(path: String) async throws -> FileDiff {
        let result = try await runner.runRaw([
            "diff", "--no-color", "--no-ext-diff", "-U3", "--no-index", "--", "/dev/null", path,
        ])
        guard result.exitCode == 0 || result.exitCode == 1 else {
            throw GitError.commandFailed(command: "diff --no-index", exitCode: result.exitCode,
                                         stderr: result.stderr)
        }
        var diff = DiffParser.parse(result.stdoutString, fallbackPath: path)
        diff = FileDiff(path: path, oldPath: diff.oldPath, isBinary: diff.isBinary,
                        isNew: true, isDeleted: false, hunks: diff.hunks)
        return diff
    }

    // MARK: - Mutations

    public func stage(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await runner.run(["add", "--"] + paths)
    }

    public func stageAll() async throws {
        try await runner.run(["add", "-A"])
    }

    public func unstage(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        // `restore --staged` requires HEAD; fall back to `rm --cached` for an unborn branch.
        let result = try await runner.runRaw(["restore", "--staged", "--"] + paths)
        if !result.succeeded {
            try await runner.run(["reset", "-q", "--"] + paths)
        }
    }

    public func discard(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        // `git restore` fails atomically if any pathspec doesn't match a tracked file, so we
        // revert each path independently: tracked paths get restored, untracked ones error
        // harmlessly and are then removed by `git clean`.
        for path in paths {
            _ = try? await runner.runRaw(["restore", "--worktree", "--", path])
        }
        _ = try? await runner.runRaw(["clean", "-fd", "--"] + paths)
    }

    public func commit(message: String, amend: Bool) async throws {
        var args = ["commit", "-m", message]
        if amend { args.append("--amend") }
        try await runner.run(args)
    }

    public func lastCommitMessage() async throws -> String {
        let result = try await runner.runRaw(["log", "-1", "--pretty=%B"])
        guard result.succeeded else { return "" }
        return result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
