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

    public func applyHunk(fileHeader: String, hunkText: String, reverse: Bool) async throws {
        // Assemble a minimal, newline-terminated patch and apply it to the index.
        var patch = fileHeader
        if !patch.hasSuffix("\n") { patch += "\n" }
        patch += hunkText
        if !patch.hasSuffix("\n") { patch += "\n" }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitify-\(UUID().uuidString).patch")
        try patch.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        var args = ["apply", "--cached", "--whitespace=nowarn"]
        if reverse { args.append("--reverse") }
        args.append(tmp.path)
        try await runner.run(args)
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

    // MARK: - Remotes & reflog

    public func remotes() async throws -> [GitRemote] {
        let output = try await runner.runString(["remote", "-v"])
        return RemoteParser.parse(output)
    }

    public func reflog(limit: Int) async throws -> [ReflogEntry] {
        let format = ["%gd", "%H", "%gs", "%cI"].joined(separator: unitSeparator)
        let output = try await runner.runString(["reflog", "--format=\(format)", "-n", "\(limit)"])
        return ReflogParser.parse(output)
    }

    /// Rejects user-supplied positional arguments beginning with `-`, which git would
    /// otherwise treat as options (argv flag smuggling). Returns the value when safe.
    @discardableResult
    static func requireSafe(_ value: String, _ label: String) throws -> String {
        if value.hasPrefix("-") {
            throw GitError.invalidArgument("\(label) may not begin with '-': \(value)")
        }
        return value
    }

    // MARK: - Branches & tags

    public func checkout(_ revision: String) async throws {
        try Self.requireSafe(revision, "revision")
        try await runner.run(["checkout", revision])
    }

    public func createBranch(name: String, startPoint: String?, checkout: Bool) async throws {
        try Self.requireSafe(name, "branch name")
        if let startPoint { try Self.requireSafe(startPoint, "start point") }
        let verb = checkout ? ["switch", "-c"] : ["branch"]
        var args = verb + [name]
        if let startPoint { args.append(startPoint) }
        try await runner.run(args)
    }

    public func deleteBranch(name: String, force: Bool) async throws {
        try Self.requireSafe(name, "branch name")
        try await runner.run(["branch", force ? "-D" : "-d", "--", name])
    }

    public func renameBranch(from oldName: String, to newName: String) async throws {
        try Self.requireSafe(oldName, "branch name")
        try Self.requireSafe(newName, "branch name")
        try await runner.run(["branch", "-m", "--", oldName, newName])
    }

    public func createTag(name: String, target: String?, message: String?) async throws {
        try Self.requireSafe(name, "tag name")
        if let target { try Self.requireSafe(target, "tag target") }
        var args = ["tag"]
        if let message { args.append(contentsOf: ["-a", "-m", message]) }
        args.append(name)
        if let target { args.append(target) }
        try await runner.run(args)
    }

    public func deleteTag(name: String) async throws {
        try Self.requireSafe(name, "tag name")
        try await runner.run(["tag", "-d", "--", name])
    }

    // MARK: - Stashes

    public func stashPush(message: String?, includeUntracked: Bool) async throws {
        var args = ["stash", "push"]
        if includeUntracked { args.append("--include-untracked") }
        if let message { args.append(contentsOf: ["-m", message]) }
        try await runner.run(args)
    }

    public func stashApply(_ selector: String) async throws {
        try Self.requireSafe(selector, "stash")
        try await runner.run(["stash", "apply", selector])
    }

    public func stashPop(_ selector: String) async throws {
        try Self.requireSafe(selector, "stash")
        try await runner.run(["stash", "pop", selector])
    }

    public func stashDrop(_ selector: String) async throws {
        try Self.requireSafe(selector, "stash")
        try await runner.run(["stash", "drop", selector])
    }

    // MARK: - Worktrees

    public func addWorktree(path: String, branch: String?, createBranch: Bool) async throws {
        try Self.requireSafe(path, "worktree path")
        if let branch { try Self.requireSafe(branch, "branch name") }
        var args = ["worktree", "add"]
        if createBranch, let branch { args.append(contentsOf: ["-b", branch]) }
        args.append(contentsOf: ["--", path])
        if !createBranch, let branch { args.append(branch) }
        try await runner.run(args)
    }

    public func removeWorktree(path: String, force: Bool) async throws {
        try Self.requireSafe(path, "worktree path")
        var args = ["worktree", "remove"]
        if force { args.append("--force") }
        args.append(path)
        try await runner.run(args)
    }

    public func pruneWorktrees() async throws {
        try await runner.run(["worktree", "prune"])
    }

    // MARK: - Network

    public func fetch(remote: String?, onProgress: (@Sendable (String) -> Void)?) async throws {
        var args = ["fetch", "--progress", "--prune"]
        if let remote { args.append(try Self.requireSafe(remote, "remote")) } else { args.append("--all") }
        try await runner.runStreaming(args, onProgress: onProgress)
    }

    public func pull(onProgress: (@Sendable (String) -> Void)?) async throws {
        try await runner.runStreaming(["pull", "--progress"], onProgress: onProgress)
    }

    public func push(remote: String?, branch: String?, setUpstream: Bool,
                     onProgress: (@Sendable (String) -> Void)?) async throws {
        var args = ["push", "--progress"]
        if setUpstream { args.append("--set-upstream") }
        if let remote { args.append(try Self.requireSafe(remote, "remote")) }
        if let branch { args.append(try Self.requireSafe(branch, "branch")) }
        try await runner.runStreaming(args, onProgress: onProgress)
    }

    // MARK: - Merge & rebase

    public func mergePreview(branch: String) async throws -> MergePreview {
        try Self.requireSafe(branch, "branch")
        let result = try await runner.runRaw(["merge-tree", "--write-tree", "-z", "--name-only", "HEAD", branch])
        if result.succeeded { return MergePreview(conflictingFiles: []) }
        guard result.exitCode == 1 else {
            throw GitError.commandFailed(command: "merge-tree", exitCode: result.exitCode, stderr: result.stderr)
        }
        // Output: <tree-oid>\0<file>\0...\0\0<messages>. Conflicted files are the entries
        // after the tree OID up to the first empty (section-separator) entry.
        let parts = result.stdoutString.components(separatedBy: "\u{0}")
        var files: [String] = []
        for part in parts.dropFirst() {
            if part.isEmpty { break }
            files.append(part)
        }
        return MergePreview(conflictingFiles: files)
    }

    public func merge(branch: String, squash: Bool, noFastForward: Bool,
                      noCommit: Bool, skipHooks: Bool) async throws {
        try Self.requireSafe(branch, "branch")
        var args = ["merge"]
        if squash {
            args.append("--squash")
        } else {
            if noFastForward { args.append("--no-ff") }
            if noCommit { args.append("--no-commit") }
        }
        if skipHooks { args.append("--no-verify") }
        args.append(branch)
        try await runner.run(args)
    }

    public func rebase(onto branch: String) async throws {
        try Self.requireSafe(branch, "branch")
        try await runner.run(["rebase", branch])
    }

    public func abortMerge() async throws {
        try await runner.run(["merge", "--abort"])
    }

    public func abortRebase() async throws {
        try await runner.run(["rebase", "--abort"])
    }

    public func currentOperation() async -> RepositoryOperation? {
        if let head = try? await runner.runRaw(["rev-parse", "--verify", "--quiet", "MERGE_HEAD"]),
           head.succeeded {
            return .merge
        }
        // A rebase leaves a rebase-merge / rebase-apply directory under the git dir.
        if let gitDir = try? await runner.runRaw(["rev-parse", "--git-path", "rebase-merge"]) {
            let path = gitDir.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            if FileManager.default.fileExists(atPath: path) { return .rebase }
        }
        if let gitDir = try? await runner.runRaw(["rev-parse", "--git-path", "rebase-apply"]) {
            let path = gitDir.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            if FileManager.default.fileExists(atPath: path) { return .rebase }
        }
        return nil
    }

    // MARK: - Clone (repository-independent)

    /// Clones `url` into a new directory named after the repo (or `name`) under `parent`,
    /// returning the path to the created working tree.
    public static func clone(
        url: String, into parent: URL, name: String? = nil,
        executablePath: String? = nil,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> URL {
        // Reject flag-smuggling URLs/folders; `--` stops option parsing of the positionals.
        // `ext::`/`fd::` command-exec protocols are already blocked via GIT_ALLOW_PROTOCOL.
        try requireSafe(url, "clone URL")
        let folder = name ?? defaultCloneFolderName(for: url)
        try requireSafe(folder, "destination folder")
        let destination = parent.appendingPathComponent(folder)
        let runner = GitRunner(workingDirectory: parent, executablePath: executablePath)
        try await runner.runStreaming(["clone", "--progress", "--", url, folder], onProgress: onProgress)
        return destination
    }

    /// Derives the default checkout folder from a clone URL (strips `.git`).
    static func defaultCloneFolderName(for url: String) -> String {
        var last = url
        if let slash = url.lastIndex(where: { $0 == "/" || $0 == ":" }) {
            last = String(url[url.index(after: slash)...])
        }
        if last.hasSuffix(".git") { last = String(last.dropLast(4)) }
        return last.isEmpty ? "repository" : last
    }
}
