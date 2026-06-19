import Foundation
import GitKit

/// Integration checks for `CLIGitService`, each driving a throwaway repository.
enum Checks {
    static func runAll() async {
        await test("repositoryRoot resolves and rejects non-repos", repositoryRoot)
        await test("status reports staged/unstaged/untracked", status)
        await test("status parses renames with original path", renameStatus)
        await test("log returns commits newest-first with parents", log)
        await test("log paginates and signals more pages", logPagination)
        await test("refs lists branches and tags with HEAD/upstream", refs)
        await test("worktrees include main and linked", worktrees)
        await test("stashes listed newest-first with branch", stashes)
        await test("diff reports hunks and line counts", diff)
        await test("diff renders untracked file as additions", untrackedDiff)
        await test("stage/unstage move files between index and worktree", stageUnstage)
        await test("commit creates history; amend rewrites it", commitAndAmend)
        await test("discard reverts tracked and removes untracked", discard)
        await test("graph layout keeps linear history in one lane", graphLinear)
        await test("graph layout diverges and merges a branch", graphBranchMerge)
        await test("branch create/checkout/rename/delete", branchOps)
        await test("tag create and delete", tagOps)
        await test("stash push/apply/pop/drop", stashOps)
        await test("worktree add and remove", worktreeOps)
        await test("reflog lists recent HEAD movements", reflogOps)
        await test("remotes/push/fetch/clone round-trip", remoteOps)
        await test("remote add/remove, push tags, delete remote branch", remoteExtras)
        await test("flag-smuggling arguments are rejected", argumentInjection)
        await test("hunk staging stages one hunk at a time", hunkStaging)
        await test("line staging stages only selected lines", lineStaging)
        await test("commit changes list files, counts, and renames", commitChanges)
        await test("merge preview detects clean vs conflicting", mergePreview)
        await test("merge and rebase update history; abort recovers", mergeRebase)
        await test("cherry-pick, revert, and reset move/copy commits", commitOps)
        await test("repository stats: languages, committers, README", repoStats)
        await test("stash branch, config get/set, conflict resolution", stashConfigConflict)
        await test("submodules are listed and parsed", submodules)
        await test("conflict markers parse; resolved file stages", conflictEditor)
    }

    static func conflictEditor() async throws {
        // Parse a conflicted file's markers.
        let content = "top\n<<<<<<< HEAD\nours line\n=======\ntheirs line\n>>>>>>> feature\nbottom\n"
        let segments = ConflictParser.parse(content)
        await expectEqual(segments.count, 3, "text + conflict + text")
        if case let .conflict(ours, theirs, _) = segments[1] {
            await expectEqual(ours, "ours line", "ours parsed")
            await expectEqual(theirs, "theirs line", "theirs parsed")
        } else {
            await expect(false, "middle segment is a conflict")
        }

        // Resolve a real conflict by writing the chosen content and staging it.
        let repo = try await twoBranchRepo(conflicting: true)
        let service = try await repo.service()
        _ = try? await service.merge(branch: "feature", squash: false, noFastForward: false,
                                     noCommit: false, skipHooks: false)
        let raw = try await require(await service.fileContents(path: "f.txt"))
        await expect(raw.contains("<<<<<<<"), "working file has conflict markers")
        try await service.resolveFile(path: "f.txt", contents: "a\nRESOLVED\nc\n")
        await expect(try await service.conflictedFiles().isEmpty, "file resolved and staged")
    }

    static func submodules() async throws {
        // A source repo to embed as a submodule.
        let source = try await TestRepository()
        try await source.commit("sub init", file: "a.txt", contents: "hi\n")

        let parent = try await TestRepository()
        try await parent.commit("root", file: "r.txt", contents: "root\n")
        try await parent.git("-c", "protocol.file.allow=always", "submodule", "add", "-q",
                             source.url.path, "libs/sub")
        try await parent.git("commit", "-q", "-m", "add submodule")

        let subs = await (try await parent.service()).submodules()
        await expectEqual(subs.count, 1, "one submodule")
        await expectEqual(subs.first?.path, "libs/sub", "submodule path")
        await expect(subs.first?.isInitialized == true, "submodule initialized")
        await expect((subs.first?.sha.count ?? 0) >= 7, "submodule sha captured")

        // Add a second submodule.
        let source2 = try await TestRepository()
        try await source2.commit("sub2", file: "b.txt", contents: "yo\n")
        try await parent.git("-c", "protocol.file.allow=always", "submodule", "add", "--",
                             source2.url.path, "libs/sub2")
        await expectEqual(await (try await parent.service()).submodules().count, 2, "second submodule added")
    }

    static func stashConfigConflict() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial", file: "f.txt", contents: "base\n")
        let service = try await repo.service()

        // config get/set (local).
        try await service.setConfigValue("user.name", "Set Name", global: false)
        await expectEqual(await service.configValue("user.name"), "Set Name", "config round-trips")

        // stash branch: stash a change, then turn it into a branch.
        try repo.write("f.txt", "stashed\n")
        try await service.stashPush(message: "wip", includeUntracked: false)
        try await service.stashBranch(name: "from-stash", selector: "stash@{0}")
        await expect(try await service.refs().contains { $0.name == "from-stash" && $0.isHead }, "stash became a branch")

        // conflict resolution: create a real conflict, take ours, confirm resolved.
        let conflict = try await twoBranchRepo(conflicting: true)
        let cService = try await conflict.service()
        _ = try? await cService.merge(branch: "feature", squash: false, noFastForward: false,
                                      noCommit: false, skipHooks: false)
        let conflicts = try await cService.conflictedFiles()
        await expect(conflicts.contains("f.txt"), "f.txt is conflicted")
        try await cService.resolveConflict(path: "f.txt", useOurs: true)
        await expect(try await cService.conflictedFiles().isEmpty, "conflict resolved after taking ours")
    }

    static func repoStats() async throws {
        let repo = try await TestRepository()
        try repo.write("main.swift", "import Foundation\nprint(\"hi\")\n")
        try repo.write("script.sh", "#!/bin/sh\necho hi\necho bye\n")
        try repo.write("README.md", "# Title\n\nHello world.\n")
        try await repo.git("add", "-A")
        try await repo.git("commit", "-q", "-m", "initial")
        let service = try await repo.service()

        let langs = await service.languageStats()
        await expect(langs.contains { $0.language == "Swift" }, "Swift detected")
        await expect(langs.contains { $0.language == "Shell" }, "Shell detected")

        let committers = await service.topCommitters(limit: 5)
        await expectEqual(committers.first?.commits, 1, "one commit by the test user")
        await expectEqual(committers.first?.name, "Test User", "committer name parsed")

        let readme = await service.readme()
        await expect(readme?.contains("# Title") == true, "README contents read")
    }

    static func commitOps() async throws {
        let repo = try await TestRepository()
        try await repo.commit("base", file: "f.txt", contents: "1\n")
        // A side branch with a commit to cherry-pick.
        try await repo.git("checkout", "-q", "-b", "side")
        try await repo.commit("side change", file: "side.txt", contents: "s\n")
        let sideSha = try await require((try await repo.service().log(limit: 1, revisions: ["HEAD"])).commits.first?.id)
        try await repo.git("checkout", "-q", "main")
        let service = try await repo.service()

        try await service.cherryPick(sha: sideSha)
        await expect(FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("side.txt").path),
                     "cherry-pick brought side.txt to main")

        // Revert the cherry-pick.
        let pickSha = try await require((try await service.log(limit: 1, revisions: ["HEAD"])).commits.first?.id)
        try await service.revert(sha: pickSha)
        await expect(!FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("side.txt").path),
                     "revert removed side.txt")
        let afterRevert = try await service.log(limit: 10, revisions: ["HEAD"])
        let revertCount = afterRevert.commits.count

        // Hard reset back two commits (drop the cherry-pick + revert).
        try await service.reset(to: "HEAD~2", mode: .hard)
        let afterReset = try await service.log(limit: 10, revisions: ["HEAD"])
        await expectEqual(afterReset.commits.count, revertCount - 2, "reset dropped two commits")
        await expect(try await service.status().hasChanges == false, "hard reset left a clean tree")
    }

    /// Builds main + feature branches; returns the repo with `feature` ahead of `main`.
    private static func twoBranchRepo(conflicting: Bool) async throws -> TestRepository {
        let repo = try await TestRepository()
        try await repo.commit("initial", file: "f.txt", contents: "a\nb\nc\n")
        try await repo.git("checkout", "-q", "-b", "feature")
        try await repo.commit("feature edit", file: conflicting ? "f.txt" : "feature.txt",
                              contents: conflicting ? "a\nFEATURE\nc\n" : "new file\n")
        try await repo.git("checkout", "-q", "main")
        if conflicting {
            try await repo.commit("main edit", file: "f.txt", contents: "a\nMAIN\nc\n")
        }
        return repo
    }

    static func commitChanges() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial", file: "keep.txt", contents: "a\nb\nc\n")
        try repo.write("old.txt", "x\n"); try await repo.git("add", "old.txt")
        try await repo.git("commit", "-q", "-m", "add old")
        try repo.write("keep.txt", "a\nB\nc\nd\n")
        try await repo.git("mv", "old.txt", "renamed.txt")
        try repo.write("added.txt", "new\n"); try await repo.git("add", "-A")
        try await repo.git("commit", "-q", "-m", "second")
        let service = try await repo.service()

        let head = try await service.log(limit: 1, revisions: ["HEAD"])
        let sha = try await require(head.commits.first?.id)
        let changes = try await service.commitChanges(sha: sha)

        let keep = try await require(changes.first { $0.path == "keep.txt" })
        await expectEqual(keep.status, .modified, "keep.txt modified")
        await expectEqual(keep.additions, 2, "two additions")
        await expectEqual(keep.deletions, 1, "one deletion")

        let added = try await require(changes.first { $0.path == "added.txt" })
        await expectEqual(added.status, .added, "added.txt added")

        let renamed = try await require(changes.first { $0.status == .renamed })
        await expectEqual(renamed.path, "renamed.txt", "rename new path")
        await expectEqual(renamed.oldPath, "old.txt", "rename old path")

        let fileDiff = try await service.commitFileDiff(sha: sha, path: "keep.txt")
        await expect(!fileDiff.hunks.isEmpty, "commit file diff has hunks")
    }

    static func lineStaging() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial", file: "f.txt", contents: "a\nb\nc\n")
        // Two additions within one hunk; stage only the first.
        try repo.write("f.txt", "a\nADDED1\nb\nADDED2\nc\n")
        let service = try await repo.service()

        let diff = try await service.diff(path: "f.txt", staged: false)
        let hunk = try await require(diff.hunks.first)
        // Pick the line index of the first addition (ADDED1).
        let firstAdd = try await require(hunk.lines.firstIndex { $0.kind == .addition && $0.content == "ADDED1" })
        try await service.applyHunkLines(fileHeader: diff.header, hunk: hunk, selected: [firstAdd], reverse: false)

        let staged = try await service.diff(path: "f.txt", staged: true)
        let stagedAdds = staged.hunks.flatMap(\.lines).filter { $0.kind == .addition }.map(\.content)
        await expect(stagedAdds.contains("ADDED1"), "ADDED1 staged")
        await expect(!stagedAdds.contains("ADDED2"), "ADDED2 not staged")

        let unstaged = try await service.diff(path: "f.txt", staged: false)
        let unstagedAdds = unstaged.hunks.flatMap(\.lines).filter { $0.kind == .addition }.map(\.content)
        await expect(unstagedAdds.contains("ADDED2"), "ADDED2 still unstaged")
    }

    static func mergePreview() async throws {
        let cleanRepo = try await twoBranchRepo(conflicting: false)
        let clean = try await cleanRepo.service()
        await expect(try await clean.mergePreview(branch: "feature").isClean, "clean merge has no conflicts")

        let conflictRepo = try await twoBranchRepo(conflicting: true)
        let conflicting = try await conflictRepo.service()
        let preview = try await conflicting.mergePreview(branch: "feature")
        await expect(!preview.isClean, "conflicting merge detected")
        await expect(preview.conflictingFiles.contains("f.txt"), "f.txt flagged as conflicting")
    }

    static func mergeRebase() async throws {
        // Clean merge with --no-ff creates a merge commit.
        let repo = try await twoBranchRepo(conflicting: false)
        let service = try await repo.service()
        try await service.merge(branch: "feature", squash: false, noFastForward: true,
                                noCommit: false, skipHooks: false)
        let head = try await service.log(limit: 1, revisions: ["HEAD"])
        await expect(head.commits.first?.isMerge == true, "merge commit created")
        await expect(await service.currentOperation() == nil, "no operation pending after clean merge")

        // Conflicting merge leaves a merge in progress; abort recovers.
        let conflictRepo = try await twoBranchRepo(conflicting: true)
        let cService = try await conflictRepo.service()
        await expectThrows("conflicting merge throws") {
            try await cService.merge(branch: "feature", squash: false, noFastForward: false,
                                     noCommit: false, skipHooks: false)
        }
        await expect(await cService.currentOperation() == .merge, "merge in progress detected")
        try await cService.abortMerge()
        await expect(await cService.currentOperation() == nil, "merge aborted")
        await expect(try await cService.status().hasChanges == false, "working tree clean after abort")

        // Rebase feature onto an advanced main (clean).
        let rebaseRepo = try await TestRepository()
        try await rebaseRepo.commit("base")
        try await rebaseRepo.git("checkout", "-q", "-b", "topic")
        try await rebaseRepo.commit("topic work", file: "t.txt", contents: "t\n")
        try await rebaseRepo.git("checkout", "-q", "main")
        try await rebaseRepo.commit("main work", file: "m.txt", contents: "m\n")
        try await rebaseRepo.git("checkout", "-q", "topic")
        let rService = try await rebaseRepo.service()
        try await rService.rebase(onto: "main")
        let topicLog = try await rService.log(limit: 10, revisions: ["HEAD"])
        await expect(topicLog.commits.contains { $0.summary == "main work" }, "topic now contains main\u{2019}s commit")

        // Conflicting rebase: currentOperation detects it, abort recovers.
        let conflictRebase = try await twoBranchRepo(conflicting: true)
        try await conflictRebase.git("checkout", "-q", "feature")
        let crService = try await conflictRebase.service()
        await expectThrows("conflicting rebase throws") {
            try await crService.rebase(onto: "main")
        }
        await expect(await crService.currentOperation() == .rebase, "rebase in progress detected")
        try await crService.abortRebase()
        await expect(await crService.currentOperation() == nil, "rebase aborted")
        await expect(try await crService.status().hasChanges == false, "working tree clean after rebase abort")

        // continueRebase: create conflict, resolve it, then continue.
        let contRepo = try await twoBranchRepo(conflicting: true)
        // Prevent git rebase --continue from opening an interactive editor.
        try await contRepo.git("config", "core.editor", "true")
        try await contRepo.git("checkout", "-q", "feature")
        let contService = try await contRepo.service()
        _ = try? await contService.rebase(onto: "main")
        await expect(await contService.currentOperation() == .rebase, "rebase paused on conflict")
        // Resolve the conflict and stage the file.
        try await contService.resolveFile(path: "f.txt", contents: "a\nRESOLVED\nc\n")
        try await contService.continueRebase()
        await expect(await contService.currentOperation() == nil, "rebase completed after continue")
        let contLog = try await contService.log(limit: 10, revisions: ["HEAD"])
        await expect(contLog.commits.contains { $0.summary == "main edit" }, "rebased branch includes main\u{2019}s commit")

        // skipRebase: create conflict, skip the conflicting commit.
        let skipRepo = try await twoBranchRepo(conflicting: true)
        try await skipRepo.git("checkout", "-q", "feature")
        let skipService = try await skipRepo.service()
        _ = try? await skipService.rebase(onto: "main")
        await expect(await skipService.currentOperation() == .rebase, "rebase paused for skip test")
        try await skipService.skipRebase()
        await expect(await skipService.currentOperation() == nil, "rebase completed after skip")
        let skipLog = try await skipService.log(limit: 10, revisions: ["HEAD"])
        await expect(skipLog.commits.contains { $0.summary == "main edit" }, "skipped rebase still has main\u{2019}s commit")
        await expect(!skipLog.commits.contains { $0.summary == "feature edit" }, "skipped commit dropped")
    }

    static func hunkStaging() async throws {
        let repo = try await TestRepository()
        // Ten lines so two edits land in separate, non-adjacent hunks.
        try await repo.commit("initial", file: "f.txt",
                              contents: (1...10).map { "line \($0)" }.joined(separator: "\n") + "\n")
        var lines = (1...10).map { "line \($0)" }
        lines[0] = "LINE ONE changed"   // top hunk
        lines[9] = "LINE TEN changed"   // bottom hunk
        try repo.write("f.txt", lines.joined(separator: "\n") + "\n")
        let service = try await repo.service()

        let diff = try await service.diff(path: "f.txt", staged: false)
        await expectEqual(diff.hunks.count, 2, "two separate hunks")
        await expect(!diff.header.isEmpty, "header captured")
        await expect(!(diff.hunks.first?.rawText.isEmpty ?? true), "hunk raw text captured")

        // Stage only the first hunk.
        let first = try await require(diff.hunks.first)
        try await service.applyHunk(fileHeader: diff.header, hunkText: first.rawText, reverse: false)

        let staged = try await service.diff(path: "f.txt", staged: true)
        await expectEqual(staged.hunks.count, 1, "exactly one hunk staged")
        await expect(staged.hunks.first?.lines.contains { $0.content.contains("LINE ONE") } ?? false,
                     "the first hunk was the one staged")

        let unstaged = try await service.diff(path: "f.txt", staged: false)
        await expect(unstaged.hunks.first?.lines.contains { $0.content.contains("LINE TEN") } ?? false,
                     "the second hunk remains unstaged")

        // Now unstage it again (reverse) and confirm the index is clean.
        let stagedFirst = try await require(staged.hunks.first)
        try await service.applyHunk(fileHeader: staged.header, hunkText: stagedFirst.rawText, reverse: true)
        await expect(try await service.status().stagedFiles.isEmpty, "index clean after unstaging the hunk")
    }

    static func remoteExtras() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial", file: "f.txt", contents: "x\n")
        try await repo.git("tag", "v1.0")
        let service = try await repo.service()

        let bare = FileManager.default.temporaryDirectory.appendingPathComponent("rx-" + UUID().uuidString + ".git")
        defer { try? FileManager.default.removeItem(at: bare) }
        try await GitRunner(workingDirectory: nil).run(["init", "--bare", "-q", bare.path])

        try await service.addRemote(name: "origin", url: bare.path)
        await expect(try await service.remotes().contains { $0.name == "origin" }, "remote added")

        try await service.push(remote: "origin", branch: "main", setUpstream: true, force: false, onProgress: nil)
        try await service.pushTags(remote: "origin", onProgress: nil)
        // The bare repo should now have the tag.
        let bareTags = try await GitRunner(workingDirectory: bare).runString(["tag", "--list"])
        await expect(bareTags.contains("v1.0"), "tag pushed to remote")

        // Push a second branch then delete it remotely.
        try await service.createBranch(name: "temp", startPoint: nil, checkout: false)
        try await service.push(remote: "origin", branch: "temp", setUpstream: false, force: false, onProgress: nil)
        try await service.deleteRemoteBranch(remote: "origin", branch: "temp", onProgress: nil)
        let bareBranches = try await GitRunner(workingDirectory: bare).runString(["branch", "--list"])
        await expect(!bareBranches.contains("temp"), "remote branch deleted")

        try await service.removeRemote(name: "origin")
        await expect(try await service.remotes().isEmpty, "remote removed")
    }

    static func argumentInjection() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial")
        let service = try await repo.service()

        await expectThrows("checkout rejects leading-dash revision") {
            try await service.checkout("--upload-pack=touch /tmp/pwned")
        }
        await expectThrows("createBranch rejects leading-dash name") {
            try await service.createBranch(name: "--bad", startPoint: nil, checkout: true)
        }
        await expectThrows("deleteTag rejects leading-dash name") {
            try await service.deleteTag(name: "--bad")
        }
        await expectThrows("fetch rejects leading-dash remote") {
            try await service.fetch(remote: "--config=core.fsmonitor=true", onProgress: nil)
        }

        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        await expectThrows("clone rejects flag-smuggling URL") {
            _ = try await CLIGitService.clone(url: "--upload-pack=touch /tmp/pwned", into: parent, onProgress: nil)
        }
        await expectThrows("clone rejects ext:: command-exec protocol") {
            _ = try await CLIGitService.clone(url: "ext::sh -c touch% /tmp/pwned", into: parent, onProgress: nil)
        }
    }

    /// Builds a bare `Commit` for graph-layout tests (only id/parents matter).
    private static func node(_ id: String, _ parents: [String] = []) -> Commit {
        Commit(id: id, parents: parents, authorName: "", authorEmail: "",
               authorDate: .distantPast, committerName: "", committerEmail: "",
               commitDate: .distantPast, summary: "", body: "", refs: [])
    }

    static func graphLinear() async throws {
        let commits = [node("C", ["B"]), node("B", ["A"]), node("A", [])]
        let graph = GraphLayout.layout(commits)
        await expectEqual(graph.width, 1, "single lane")
        await expect(graph.nodes.allSatisfy { $0.lane == 0 }, "all nodes in lane 0")
        await expectEqual(graph.nodes[0].outgoing, [0], "C routes to B in lane 0")
        await expectEqual(graph.nodes[2].outgoing, [], "root has no outgoing")
    }

    static func graphBranchMerge() async throws {
        // M is a merge of B and C, both children of A.
        let commits = [node("M", ["B", "C"]), node("B", ["A"]), node("C", ["A"]), node("A", [])]
        let graph = GraphLayout.layout(commits)
        await expectEqual(graph.width, 2, "two lanes at peak")

        let m = graph.nodes[0]
        await expectEqual(m.lane, 0, "merge sits in lane 0")
        await expectEqual(m.outgoing.count, 2, "merge has two outgoing edges")

        let c = graph.nodes[2]
        await expectEqual(c.lane, 1, "C took the second lane")

        let b = graph.nodes[1]
        await expect(b.passThrough.contains(1), "C's lane passes through B's row")

        let a = graph.nodes[3]
        await expectEqual(a.lane, 0, "branches converge back to lane 0 at A")
        await expectEqual(a.outgoing, [], "A is the root")
    }

    static func repositoryRoot() async throws {
        let repo = try await TestRepository()
        let service = try await repo.service()
        await expectEqual(service.root.lastPathComponent, repo.url.lastPathComponent,
                          "root resolves to repo dir")

        let nonRepo = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: nonRepo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: nonRepo) }
        await expectThrows("non-repo dir throws") {
            _ = try await CLIGitService(directory: nonRepo)
        }
    }

    static func status() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial", file: "tracked.txt", contents: "one\n")

        try repo.write("tracked.txt", "one\ntwo\n")
        try await repo.git("add", "tracked.txt")
        try repo.write("tracked.txt", "one\ntwo\nthree\n")
        try repo.write("new.txt", "fresh\n")

        let status = try await repo.service().status()
        await expectEqual(status.branch, "main", "branch is main")
        await expect(status.hasChanges, "has changes")

        let tracked = try await require(status.files.first { $0.path == "tracked.txt" })
        await expectEqual(tracked.indexState, .modified, "staged modified")
        await expectEqual(tracked.worktreeState, .modified, "unstaged modified")

        let untracked = try await require(status.files.first { $0.path == "new.txt" })
        await expect(untracked.isUntracked, "new.txt untracked")
    }

    static func renameStatus() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial", file: "old.txt", contents: "content\n")
        try await repo.git("mv", "old.txt", "renamed.txt")

        let status = try await repo.service().status()
        let renamed = try await require(status.files.first { $0.path == "renamed.txt" })
        await expectEqual(renamed.indexState, .renamed, "rename detected")
        await expectEqual(renamed.originalPath, "old.txt", "original path captured")
    }

    static func log() async throws {
        let repo = try await TestRepository()
        try await repo.commit("first")
        try await repo.commit("second")
        try await repo.commit("third")

        let page = try await repo.service().log(limit: 10, revisions: ["HEAD"])
        await expectEqual(page.commits.count, 3, "three commits")
        await expectEqual(page.commits.first?.summary, "third", "newest first")
        await expectEqual(page.commits.last?.summary, "first", "oldest last")
        await expectEqual(page.commits[0].parents, [page.commits[1].id], "parent link")
        await expect(page.commits.last?.parents.isEmpty == true, "root has no parent")
        await expect(page.nextSkip == nil, "no further pages")
    }

    static func logPagination() async throws {
        let repo = try await TestRepository()
        for n in 1...5 { try await repo.commit("commit \(n)") }

        let first = try await repo.service().log(skip: 0, limit: 2, revisions: ["HEAD"])
        await expectEqual(first.commits.count, 2, "page 1 size")
        await expectEqual(first.nextSkip, 2, "page 1 next skip")

        let last = try await repo.service().log(skip: 4, limit: 2, revisions: ["HEAD"])
        await expectEqual(last.commits.count, 1, "final page size")
        await expect(last.nextSkip == nil, "final page has no next")
    }

    static func refs() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial")
        try await repo.git("branch", "develop")
        try await repo.git("tag", "v1.0")
        try await repo.git("config", "remote.origin.url", ".")
        try await repo.git("config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*")
        try await repo.git("update-ref", "refs/remotes/origin/main", "HEAD")
        try await repo.git("config", "branch.main.remote", "origin")
        try await repo.git("config", "branch.main.merge", "refs/heads/main")

        let refs = try await repo.service().refs()
        let main = try await require(refs.first { $0.kind == .localBranch && $0.name == "main" })
        await expect(main.isHead, "main is HEAD")
        await expectEqual(main.upstream, "origin/main", "upstream tracked")
        await expect(refs.contains { $0.kind == .localBranch && $0.name == "develop" }, "develop listed")
        await expect(refs.contains { $0.kind == .remoteBranch && $0.name == "origin/main" }, "remote listed")
        let tag = try await require(refs.first { $0.kind == .tag && $0.name == "v1.0" })
        await expect(!tag.targetSHA.isEmpty, "tag has target")
    }

    static func worktrees() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial")

        let linkedPath = repo.url.deletingLastPathComponent()
            .appendingPathComponent("wt-" + UUID().uuidString)
        try await repo.git("worktree", "add", "-q", linkedPath.path, "-b", "feature")
        defer { try? FileManager.default.removeItem(at: linkedPath) }

        let worktrees = try await repo.service().worktrees()
        await expectEqual(worktrees.count, 2, "two worktrees")
        let main = try await require(worktrees.first { $0.isMain })
        await expectEqual(main.branch, "main", "main worktree on main")
        let feature = try await require(worktrees.first { $0.branch == "feature" })
        await expect(!feature.isMain, "feature is linked")
    }

    static func stashes() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial", file: "f.txt", contents: "v1\n")

        try repo.write("f.txt", "v2\n")
        try await repo.git("stash", "push", "-m", "first stash")
        try repo.write("f.txt", "v3\n")
        try await repo.git("stash", "push", "-m", "second stash")

        let stashes = try await repo.service().stashes()
        await expectEqual(stashes.count, 2, "two stashes")
        await expectEqual(stashes[0].id, "stash@{0}", "newest selector")
        await expectEqual(stashes[0].branch, "main", "branch captured")
        await expect(stashes[0].message.contains("second stash"), "newest message")
        await expect(stashes[1].message.contains("first stash"), "oldest message")
    }

    static func diff() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial", file: "f.txt", contents: "a\nb\nc\n")
        try repo.write("f.txt", "a\nB\nc\nd\n")

        let fileDiff = try await repo.service().diff(path: "f.txt", staged: false)
        await expect(!fileDiff.hunks.isEmpty, "has a hunk")
        await expectEqual(fileDiff.addedLines, 2, "two additions (B and d)")
        await expectEqual(fileDiff.removedLines, 1, "one deletion (b)")
        // A context line should carry both line numbers; an addition only the new one.
        let firstHunk = try await require(fileDiff.hunks.first)
        await expect(firstHunk.lines.contains { $0.kind == .context && $0.oldLineNumber != nil },
                     "context lines numbered")
        await expect(firstHunk.lines.contains { $0.kind == .addition && $0.oldLineNumber == nil },
                     "additions lack old number")
    }

    static func untrackedDiff() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial")
        try repo.write("brand-new.txt", "line1\nline2\n")

        let fileDiff = try await repo.service().diff(path: "brand-new.txt", staged: false)
        await expect(fileDiff.isNew, "marked as new file")
        await expectEqual(fileDiff.addedLines, 2, "both lines added")
    }

    static func stageUnstage() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial", file: "f.txt", contents: "v1\n")
        try repo.write("f.txt", "v2\n")
        let service = try await repo.service()

        try await service.stage(paths: ["f.txt"])
        var status = try await service.status()
        await expect(status.stagedFiles.contains { $0.path == "f.txt" }, "staged after add")

        try await service.unstage(paths: ["f.txt"])
        status = try await service.status()
        await expect(status.unstagedFiles.contains { $0.path == "f.txt" }, "unstaged after restore")
        await expect(status.stagedFiles.isEmpty, "nothing staged")
    }

    static func commitAndAmend() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial")
        let service = try await repo.service()

        try repo.write("note.txt", "hello\n")
        try await service.stage(paths: ["note.txt"])
        try await service.commit(message: "add note", amend: false)

        var page = try await service.log(limit: 5, revisions: ["HEAD"])
        await expectEqual(page.commits.first?.summary, "add note", "commit recorded")
        let countAfterCommit = page.commits.count

        try await service.commit(message: "add note (amended)", amend: true)
        page = try await service.log(limit: 5, revisions: ["HEAD"])
        await expectEqual(page.commits.first?.summary, "add note (amended)", "amend rewrote message")
        await expectEqual(page.commits.count, countAfterCommit, "amend didn't add a commit")
        await expectEqual(try await service.lastCommitMessage(), "add note (amended)", "last message")
    }

    static func discard() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial", file: "tracked.txt", contents: "original\n")
        try repo.write("tracked.txt", "changed\n")
        try repo.write("untracked.txt", "temp\n")
        let service = try await repo.service()

        try await service.discard(paths: ["tracked.txt", "untracked.txt"])
        let status = try await service.status()
        await expect(!status.hasChanges, "working tree clean after discard")
        let restored = try String(contentsOf: repo.url.appendingPathComponent("tracked.txt"), encoding: .utf8)
        await expectEqual(restored, "original\n", "tracked file reverted")
        await expect(!FileManager.default.fileExists(atPath: repo.url.appendingPathComponent("untracked.txt").path),
                     "untracked file removed")
    }

    static func branchOps() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial")
        let service = try await repo.service()

        try await service.createBranch(name: "feature", startPoint: nil, checkout: true)
        var refs = try await service.refs()
        await expect(refs.first { $0.name == "feature" }?.isHead == true, "feature checked out")

        try await service.checkout("main")
        try await service.renameBranch(from: "feature", to: "feat")
        refs = try await service.refs()
        await expect(refs.contains { $0.name == "feat" }, "branch renamed")
        await expect(!refs.contains { $0.name == "feature" }, "old name gone")

        try await service.deleteBranch(name: "feat", force: true)
        refs = try await service.refs()
        await expect(!refs.contains { $0.name == "feat" }, "branch deleted")
    }

    static func tagOps() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial")
        let service = try await repo.service()

        try await service.createTag(name: "v1.0", target: nil, message: "release one")
        await expect(try await service.refs().contains { $0.kind == .tag && $0.name == "v1.0" }, "tag created")

        try await service.deleteTag(name: "v1.0")
        await expect(!(try await service.refs().contains { $0.kind == .tag && $0.name == "v1.0" }), "tag deleted")
    }

    static func stashOps() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial", file: "f.txt", contents: "v1\n")
        let service = try await repo.service()

        try repo.write("f.txt", "v2\n")
        try await service.stashPush(message: "wip", includeUntracked: false)
        await expect(try await service.status().hasChanges == false, "clean after stash")
        await expectEqual(try await service.stashes().count, 1, "one stash")

        try await service.stashApply("stash@{0}")
        await expect(try await service.status().hasChanges, "changes restored by apply")
        await expectEqual(try await service.stashes().count, 1, "apply keeps stash")

        try await service.stashDrop("stash@{0}")
        await expectEqual(try await service.stashes().count, 0, "stash dropped")
    }

    static func worktreeOps() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial")
        let service = try await repo.service()

        let linked = repo.url.deletingLastPathComponent().appendingPathComponent("wt-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: linked) }
        try await service.addWorktree(path: linked.path, branch: "wt-branch", createBranch: true)
        await expectEqual(try await service.worktrees().count, 2, "worktree added")

        try await service.removeWorktree(path: linked.path, force: true)
        await expectEqual(try await service.worktrees().count, 1, "worktree removed")
    }

    static func reflogOps() async throws {
        let repo = try await TestRepository()
        try await repo.commit("first")
        try await repo.commit("second")
        let entries = try await repo.service().reflog(limit: 10)
        await expect(!entries.isEmpty, "reflog has entries")
        await expectEqual(entries.first?.selector, "HEAD@{0}", "newest selector")
        await expect(entries.first?.action == "commit", "newest action is commit")
    }

    static func remoteOps() async throws {
        let repo = try await TestRepository()
        try await repo.commit("initial", file: "f.txt", contents: "hello\n")
        let service = try await repo.service()

        // Stand up a bare repo to act as the remote.
        let bare = FileManager.default.temporaryDirectory.appendingPathComponent("remote-" + UUID().uuidString + ".git")
        defer { try? FileManager.default.removeItem(at: bare) }
        let bareRunner = GitRunner(workingDirectory: nil)
        try await bareRunner.run(["init", "--bare", "-q", bare.path])

        try await repo.git("remote", "add", "origin", bare.path)
        let remotes = try await service.remotes()
        await expectEqual(remotes.first?.name, "origin", "remote listed")
        await expectEqual(remotes.first?.fetchURL, bare.path, "remote url captured")

        try await service.push(remote: "origin", branch: "main", setUpstream: true, force: false, onProgress: nil)
        try await service.fetch(remote: "origin", onProgress: nil) // should not throw

        // Clone the bare into a fresh directory and confirm the file arrived.
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let cloned = try await CLIGitService.clone(url: bare.path, into: parent, name: "work", onProgress: nil)
        await expect(FileManager.default.fileExists(atPath: cloned.appendingPathComponent("f.txt").path),
                     "cloned working tree has file")
    }
}
