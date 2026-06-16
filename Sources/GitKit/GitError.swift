import Foundation

/// Errors surfaced by the Git engine.
public enum GitError: Error, Sendable, Equatable {
    /// `git` exited with a non-zero status. Carries the exit code and captured stderr.
    case commandFailed(command: String, exitCode: Int32, stderr: String)
    /// The `git` executable could not be located or launched.
    case gitUnavailable(String)
    /// Output from git could not be parsed into the expected shape.
    case parseFailure(String)
    /// The requested path is not inside a git working tree.
    case notARepository(String)
}

extension GitError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .commandFailed(command, exitCode, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`git \(command)` failed (exit \(exitCode))" + (detail.isEmpty ? "" : ": \(detail)")
        case let .gitUnavailable(message):
            return "git is unavailable: \(message)"
        case let .parseFailure(message):
            return "Failed to parse git output: \(message)"
        case let .notARepository(path):
            return "Not a git repository: \(path)"
        }
    }
}
