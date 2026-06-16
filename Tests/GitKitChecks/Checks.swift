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
}
