import Foundation

/// Abstraction over local and SSH-based git command execution.
///
/// Both `GitRunner` (local) and `SSHGitRunner` (remote) conform to this protocol,
/// allowing `CLIGitService` to execute git commands transparently against either.
public protocol GitRunnerProtocol: Actor {
    /// Working directory for the repository. For local runners this is a filesystem URL;
    /// for SSH runners it\u{2019}s a synthetic URL representing the remote path.
    var workingDirectory: URL? { get }

    /// Runs `git <arguments>` and returns the result without throwing on non-zero exit.
    func runRaw(_ arguments: [String]) async throws -> GitProcessResult

    /// Runs `git <arguments>`, throwing on non-zero exit. Returns stdout as `Data`.
    @discardableResult
    func run(_ arguments: [String]) async throws -> Data

    /// Runs `git <arguments>`, throwing on non-zero exit. Returns stdout as a string.
    func runString(_ arguments: [String]) async throws -> String

    /// Runs `git <arguments>`, streaming stderr progress lines to `onProgress`.
    /// Throws on non-zero exit.
    @discardableResult
    func runStreaming(
        _ arguments: [String],
        onProgress: (@Sendable (String) -> Void)?
    ) async throws -> GitProcessResult
}

public extension GitRunnerProtocol {
    @discardableResult
    func runStreaming(_ arguments: [String]) async throws -> GitProcessResult {
        try await runStreaming(arguments, onProgress: nil)
    }
}
