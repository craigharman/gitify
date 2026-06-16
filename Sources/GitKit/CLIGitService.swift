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
}
