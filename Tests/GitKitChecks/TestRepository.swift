import Foundation
import GitKit

/// Builds and drives a throwaway git repository in a temp directory for integration tests.
final class TestRepository {
    let url: URL
    private let runner: GitRunner

    init() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitkit-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.url = base
        self.runner = GitRunner(workingDirectory: base)

        try await git("init", "-q", "-b", "main")
        try await git("config", "user.name", "Test User")
        try await git("config", "user.email", "test@example.com")
        try await git("config", "commit.gpgsign", "false")
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func git(_ args: String...) async throws -> String {
        String(decoding: try await runner.run(args), as: UTF8.self)
    }

    func write(_ relativePath: String, _ contents: String) throws {
        let fileURL = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Writes `relativePath`, stages it, and commits with `message`.
    func commit(_ message: String, file relativePath: String = "file.txt", contents: String? = nil) async throws {
        try write(relativePath, contents ?? message + "\n")
        try await git("add", relativePath)
        try await git("commit", "-q", "-m", message)
    }

    func service() async throws -> CLIGitService {
        try await CLIGitService(directory: url)
    }
}
