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
        var parsed = RefParser.parse(output)

        // For local branches without a configured upstream, try to infer ahead/behind
        // by comparing against a same-named remote branch (e.g. origin/<branch>), or
        // falling back to the remote's default branch (origin/HEAD).
        let remoteNames = Set(parsed.filter { $0.kind == .remoteBranch }.map { $0.name })
        let defaultRemoteRef = try? await runner.runString(
            ["symbolic-ref", "refs/remotes/origin/HEAD"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        for i in parsed.indices where parsed[i].kind == .localBranch && parsed[i].upstream == nil {
            let name = parsed[i].name
            // Prefer a same-named remote branch, then fall back to origin/HEAD.
            let remoteRef: String
            if remoteNames.contains("origin/\(name)") {
                remoteRef = "refs/remotes/origin/\(name)"
            } else if let r = remoteNames.first(where: { $0.hasSuffix("/\(name)") }) {
                remoteRef = "refs/remotes/\(r)"
            } else if let def = defaultRemoteRef, !def.isEmpty {
                remoteRef = def
            } else {
                continue
            }
            if let (ahead, behind) = try? await revListCount(
                left: remoteRef, right: "refs/heads/\(name)"
            ) {
                parsed[i] = Ref(id: parsed[i].id, kind: parsed[i].kind, name: name,
                                targetSHA: parsed[i].targetSHA, isHead: parsed[i].isHead,
                                upstream: nil, ahead: ahead, behind: behind)
            }
        }

        return parsed
    }

    /// Returns (behind, ahead) counts between two refs using `rev-list --count --left-right`.
    private func revListCount(left: String, right: String) async throws -> (Int, Int)? {
        let output = try await runner.runString([
            "rev-list", "--count", "--left-right", "\(left)...\(right)",
        ])
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\t")
        guard parts.count == 2, let l = Int(parts[0]), let r = Int(parts[1]) else { return nil }
        return (r, l) // right = ahead, left = behind
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

    // MARK: - Commit changes

    public func commitChanges(sha: String) async throws -> [FileChange] {
        try Self.requireSafe(sha, "commit")
        let nameStatus = try await runner.runString(["show", sha, "--format=", "--name-status", "-z"])
        let numstat = try await runner.runString(["show", sha, "--format=", "--numstat", "-z"])
        return CommitChangesParser.parse(nameStatus: nameStatus, numstat: numstat)
    }

    public func commitFileDiff(sha: String, path: String) async throws -> FileDiff {
        try Self.requireSafe(sha, "commit")
        let output = try await runner.runString([
            "show", sha, "--format=", "--no-color", "--no-ext-diff", "-U3", "--", path,
        ])
        return DiffParser.parse(output, fallbackPath: path)
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

    /// Removes files from the index but keeps them on disk (`git rm --cached`).
    public func untrack(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await runner.run(["rm", "--cached", "-r", "--"] + paths)
    }

    /// Appends patterns to the repository's `.gitignore`, creating it if needed.
    public func addToGitignore(patterns: [String]) throws {
        guard !patterns.isEmpty else { return }
        let gitignore = root.appendingPathComponent(".gitignore")
        var existing = (try? String(contentsOf: gitignore, encoding: .utf8)) ?? ""
        // Ensure we start on a new line.
        if !existing.isEmpty && !existing.hasSuffix("\n") { existing += "\n" }
        existing += patterns.joined(separator: "\n") + "\n"
        try existing.write(to: gitignore, atomically: true, encoding: .utf8)
    }

    public func applyHunk(fileHeader: String, hunkText: String, reverse: Bool) async throws {
        var patch = fileHeader
        if !patch.hasSuffix("\n") { patch += "\n" }
        patch += hunkText
        if !patch.hasSuffix("\n") { patch += "\n" }
        try await applyPatch(patch, reverse: reverse)
    }

    public func applyHunkLines(fileHeader: String, hunk: DiffHunk,
                               selected: Set<Int>, reverse: Bool) async throws {
        // Build a partial-hunk patch: keep context, include selected +/- lines, drop
        // unselected additions, and turn unselected deletions back into context. git's
        // `--recount` recomputes the line counts so the header need not be exact.
        var body = ""
        var oldCount = 0, newCount = 0
        var changed = false
        for (i, line) in hunk.lines.enumerated() {
            switch line.kind {
            case .context:
                body += " \(line.content)\n"; oldCount += 1; newCount += 1
            case .addition:
                if selected.contains(i) { body += "+\(line.content)\n"; newCount += 1; changed = true }
            case .deletion:
                if selected.contains(i) {
                    body += "-\(line.content)\n"; oldCount += 1; changed = true
                } else {
                    body += " \(line.content)\n"; oldCount += 1; newCount += 1
                }
            }
        }
        guard changed else { return }

        // Drop the `index <blob>..<blob>` line: for a partial patch the new blob hash won't
        // match, and git would reject the patch.
        var patch = Self.strippingIndexLine(fileHeader)
        if !patch.hasSuffix("\n") { patch += "\n" }
        patch += "@@ -\(hunk.oldStart),\(oldCount) +\(hunk.newStart),\(newCount) @@\n"
        patch += body
        try await applyPatch(patch, reverse: reverse, recount: true)
    }

    private static func strippingIndexLine(_ header: String) -> String {
        header.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("index ") }
            .joined(separator: "\n")
    }

    private func applyPatch(_ patch: String, reverse: Bool, recount: Bool = false) async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitify-\(UUID().uuidString).patch")
        try patch.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        var args = ["apply", "--cached", "--whitespace=nowarn"]
        if recount { args.append("--recount") }
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

    public func stashBranch(name: String, selector: String) async throws {
        try Self.requireSafe(name, "branch name")
        try Self.requireSafe(selector, "stash")
        try await runner.run(["stash", "branch", name, selector])
    }

    // MARK: - Config & conflicts

    public func configValue(_ key: String) async -> String? {
        guard (try? Self.requireSafe(key, "key")) != nil else { return nil }
        guard let result = try? await runner.runRaw(["config", "--get", key]), result.succeeded else { return nil }
        let value = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public func setConfigValue(_ key: String, _ value: String, global: Bool) async throws {
        try Self.requireSafe(key, "key")
        var args = ["config"]
        if global { args.append("--global") }
        args.append(contentsOf: [key, value]) // key is validated; value is positional
        try await runner.run(args)
    }

    public func submodules() async -> [Submodule] {
        guard let output = try? await runner.runString(["submodule", "status"]) else { return [] }
        return SubmoduleParser.parse(output)
    }

    public func updateSubmodules(path: String?) async throws {
        var args = ["submodule", "update", "--init", "--recursive"]
        if let path { args.append(contentsOf: ["--", try Self.requireSafe(path, "path")]) }
        try await runner.runStreaming(args)
    }

    public func addSubmodule(url: String, path: String) async throws {
        try Self.requireSafe(url, "submodule URL")
        try Self.requireSafe(path, "submodule path")
        try await runner.runStreaming(["submodule", "add", "--", url, path])
    }

    public func conflictedFiles() async throws -> [String] {
        let output = try await runner.run(["diff", "--name-only", "--diff-filter=U", "-z"])
        return String(decoding: output, as: UTF8.self)
            .split(separator: "\u{0}", omittingEmptySubsequences: true).map(String.init)
    }

    public func resolveConflict(path: String, useOurs: Bool) async throws {
        try Self.requireSafe(path, "path")
        try await runner.run(["checkout", useOurs ? "--ours" : "--theirs", "--", path])
        try await runner.run(["add", "--", path])
    }

    public func fileContents(path: String) async -> String? {
        try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    public func resolveFile(path: String, contents: String) async throws {
        try Self.requireSafe(path, "path")
        try contents.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
        try await runner.run(["add", "--", path])
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

    public func pull(rebase: Bool, noRebase: Bool, onProgress: (@Sendable (String) -> Void)?) async throws {
        var args = ["pull", "--progress"]
        if rebase { args.append("--rebase") }
        else if noRebase { args.append("--no-rebase") }
        try await runner.runStreaming(args, onProgress: onProgress)
    }

    public func push(remote: String?, branch: String?, setUpstream: Bool, force: Bool,
                     onProgress: (@Sendable (String) -> Void)?) async throws {
        var args = ["push", "--progress"]
        if setUpstream { args.append("--set-upstream") }
        if force { args.append("--force-with-lease") }
        if let remote { args.append(try Self.requireSafe(remote, "remote")) }
        if let branch { args.append(try Self.requireSafe(branch, "branch")) }
        try await runner.runStreaming(args, onProgress: onProgress)
    }

    public func pushTags(remote: String?, onProgress: (@Sendable (String) -> Void)?) async throws {
        var args = ["push", "--progress", "--tags"]
        if let remote { args.append(try Self.requireSafe(remote, "remote")) }
        try await runner.runStreaming(args, onProgress: onProgress)
    }

    public func deleteRemoteBranch(remote: String, branch: String,
                                   onProgress: (@Sendable (String) -> Void)?) async throws {
        try Self.requireSafe(remote, "remote")
        try Self.requireSafe(branch, "branch")
        try await runner.runStreaming(["push", "--progress", remote, "--delete", branch], onProgress: onProgress)
    }

    public func addRemote(name: String, url: String) async throws {
        try Self.requireSafe(name, "remote name")
        try Self.requireSafe(url, "remote URL")
        try await runner.run(["remote", "add", "--", name, url])
    }

    public func removeRemote(name: String) async throws {
        try Self.requireSafe(name, "remote name")
        try await runner.run(["remote", "remove", name])
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

    public func cherryPick(sha: String) async throws {
        try Self.requireSafe(sha, "commit")
        try await runner.run(["cherry-pick", sha])
    }

    public func revert(sha: String) async throws {
        try Self.requireSafe(sha, "commit")
        try await runner.run(["revert", "--no-edit", sha])
    }

    public func reset(to sha: String, mode: ResetMode) async throws {
        try Self.requireSafe(sha, "commit")
        try await runner.run(["reset", "--\(mode.rawValue)", sha])
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

    // MARK: - Repository stats

    public func languageStats() async -> [LanguageStat] {
        guard let listing = try? await runner.runString(["ls-files", "-z"]) else { return [] }
        let paths = listing.split(separator: "\u{0}").map(String.init)
        let root = self.root
        // File reading is done off the calling context to avoid blocking the UI.
        return await Task.detached(priority: .utility) {
            var byLanguage: [String: (lines: Int, files: Int)] = [:]
            for path in paths {
                let url = root.appendingPathComponent(path)
                guard let data = try? Data(contentsOf: url), !data.isEmpty,
                      data.count < 5_000_000,                       // skip very large files
                      !data.prefix(8000).contains(0) else { continue } // skip binary
                let lines = data.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
                let language = Self.language(for: (path as NSString).pathExtension.lowercased())
                var entry = byLanguage[language] ?? (0, 0)
                entry.lines += max(lines, 1)
                entry.files += 1
                byLanguage[language] = entry
            }
            return byLanguage
                .map { LanguageStat(language: $0.key, lines: $0.value.lines, files: $0.value.files) }
                .sorted { $0.lines > $1.lines }
        }.value
    }

    public func topCommitters(limit: Int) async -> [Committer] {
        guard let output = try? await runner.runString(["shortlog", "-sne", "HEAD"]) else { return [] }
        var committers: [Committer] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let tab = trimmed.firstIndex(of: "\t"),
                  let count = Int(trimmed[..<tab].trimmingCharacters(in: .whitespaces)) else { continue }
            let rest = String(trimmed[trimmed.index(after: tab)...])
            if let lt = rest.lastIndex(of: "<"), let gt = rest.lastIndex(of: ">"), lt < gt {
                let name = String(rest[..<lt]).trimmingCharacters(in: .whitespaces)
                let email = String(rest[rest.index(after: lt)..<gt])
                committers.append(Committer(name: name, email: email, commits: count))
            } else {
                committers.append(Committer(name: rest, email: "", commits: count))
            }
        }
        return Array(committers.prefix(limit))
    }

    public func readme() async -> String? {
        let candidates = ["README.md", "README.markdown", "README.txt", "README", "README.rst"]
        for name in candidates {
            let url = root.appendingPathComponent(name)
            if let contents = try? String(contentsOf: url, encoding: .utf8) { return contents }
        }
        return nil
    }

    /// Maps a lowercased file extension to a human-readable language name.
    static func language(for ext: String) -> String {
        let map: [String: String] = [
            "swift": "Swift", "m": "Objective-C", "mm": "Objective-C++", "h": "C/C++ Header",
            "c": "C", "cc": "C++", "cpp": "C++", "cxx": "C++", "hpp": "C++ Header",
            "js": "JavaScript", "jsx": "JavaScript", "ts": "TypeScript", "tsx": "TypeScript",
            "py": "Python", "rb": "Ruby", "go": "Go", "rs": "Rust", "java": "Java", "kt": "Kotlin",
            "sh": "Shell", "bash": "Shell", "zsh": "Shell", "pl": "Perl", "php": "PHP",
            "md": "Markdown", "markdown": "Markdown", "rst": "reStructuredText",
            "yml": "YAML", "yaml": "YAML", "json": "JSON", "toml": "TOML", "xml": "XML",
            "html": "HTML", "css": "CSS", "scss": "SCSS", "sql": "SQL",
            "txt": "Plain Text", "": "Other",
        ]
        return map[ext] ?? ext.uppercased()
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
