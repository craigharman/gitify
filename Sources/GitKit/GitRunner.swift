import Foundation

/// The result of running a `git` process.
public struct GitProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: String

    public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    public var succeeded: Bool { exitCode == 0 }
}

/// A streamed line of progress emitted on `git`'s stderr (e.g. clone/fetch/push).
public struct GitProgressLine: Sendable {
    public let text: String
}

/// Mutable storage shared across the pipe-reading dispatch closures. Access is synchronized
/// by the surrounding `DispatchGroup` (writes complete before `group.wait()` returns), so
/// `@unchecked Sendable` is sound here.
private final class CaptureBox: @unchecked Sendable {
    var stdout = Data()
    var stderr = Data()
    var stderrText = ""
}

/// Serializes invocations of the user's `git` binary for a single repository.
///
/// We shell out to the installed `git` (rather than libgit2) so that semantics,
/// config, and credentials always match the user's environment, and so advanced
/// features (worktrees, complex rebases) work without libgit2's gaps.
///
/// An actor enforces one mutating invocation at a time per repository, avoiding
/// `index.lock` contention while still allowing concurrency across repositories.
public actor GitRunner {
    /// Working directory for invocations. `nil` for repo-independent commands (e.g. clone, version).
    public let workingDirectory: URL?
    private let executableURL: URL

    /// Environment applied to every invocation. We disable interactive prompts so that
    /// missing credentials surface as errors rather than hanging on a TTY read.
    private static let baseEnvironment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        env["LC_ALL"] = "C"
        // Prevent git from trying to open an interactive editor (e.g. during rebase
        // --continue). The GUI supplies messages via -m / -F where needed.
        env["GIT_EDITOR"] = "true"
        // Restrict transports to well-known ones, blocking command-executing pseudo-protocols
        // like `ext::` / `fd::` that a malicious clone/remote URL could otherwise smuggle.
        env["GIT_ALLOW_PROTOCOL"] = "https:http:ssh:git:file"
        return env
    }()

    public init(workingDirectory: URL?, executablePath: String? = nil) {
        self.workingDirectory = workingDirectory
        self.executableURL = URL(fileURLWithPath: executablePath ?? GitRunner.defaultGitPath)
    }

    /// Best-effort discovery of the `git` binary. Falls back to the common Apple path.
    public static let defaultGitPath: String = {
        let candidates = ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/usr/bin/git"
    }()

    /// Runs `git <arguments>` and returns the captured result without throwing on non-zero exit.
    ///
    /// The entire invocation runs on a background dispatch queue — never the Swift
    /// cooperative thread pool — so the blocking `waitUntilExit()` cannot starve it. Both
    /// pipes are drained concurrently on their own queues before we wait, avoiding the
    /// classic Foundation deadlock when output exceeds the pipe buffer.
    public func runRaw(_ arguments: [String]) async throws -> GitProcessResult {
        let executableURL = self.executableURL
        let workingDirectory = self.workingDirectory
        let environment = GitRunner.baseEnvironment

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments
                process.environment = environment
                if let workingDirectory {
                    process.currentDirectoryURL = workingDirectory
                }

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let box = CaptureBox()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    box.stdout = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    box.stderr = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                    group.leave()
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: GitError.gitUnavailable(
                        "\(executableURL.path): \(error.localizedDescription)"))
                    return
                }

                process.waitUntilExit()
                group.wait() // ensure both pipes fully drained before reporting

                continuation.resume(returning: GitProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: box.stdout,
                    stderr: String(decoding: box.stderr, as: UTF8.self)
                ))
            }
        }
    }

    /// Runs `git <arguments>`, throwing `GitError.commandFailed` on a non-zero exit.
    /// Returns stdout as `Data` to support `-z` (NUL-delimited) output.
    @discardableResult
    public func run(_ arguments: [String]) async throws -> Data {
        let result = try await runRaw(arguments)
        guard result.succeeded else {
            throw GitError.commandFailed(
                command: arguments.joined(separator: " "),
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        return result.stdout
    }

    /// Convenience: run and decode stdout as a UTF-8 string.
    public func runString(_ arguments: [String]) async throws -> String {
        String(decoding: try await run(arguments), as: UTF8.self)
    }

    /// Runs `git <arguments>`, streaming stderr progress lines to `onProgress` as they
    /// arrive (git writes `--progress` output to stderr, updating in place with `\r`).
    /// Throws `GitError.commandFailed` on a non-zero exit.
    @discardableResult
    public func runStreaming(
        _ arguments: [String],
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> GitProcessResult {
        let executableURL = self.executableURL
        let workingDirectory = self.workingDirectory
        let environment = GitRunner.baseEnvironment

        let result: GitProcessResult = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments
                process.environment = environment
                if let workingDirectory { process.currentDirectoryURL = workingDirectory }

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let box = CaptureBox()
                let group = DispatchGroup()

                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    box.stdout = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let handle = stderrPipe.fileHandleForReading
                    var pending = ""
                    while case let chunk = handle.availableData, !chunk.isEmpty {
                        let text = String(decoding: chunk, as: UTF8.self)
                        box.stderrText += text
                        pending += text
                        // Progress updates are delimited by \r or \n.
                        var line = ""
                        for character in pending {
                            if character == "\r" || character == "\n" {
                                let trimmed = line.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty { onProgress?(trimmed) }
                                line = ""
                            } else {
                                line.append(character)
                            }
                        }
                        pending = line
                    }
                    group.leave()
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: GitError.gitUnavailable(
                        "\(executableURL.path): \(error.localizedDescription)"))
                    return
                }

                process.waitUntilExit()
                group.wait()
                continuation.resume(returning: GitProcessResult(
                    exitCode: process.terminationStatus, stdout: box.stdout, stderr: box.stderrText))
            }
        }

        guard result.succeeded else {
            throw GitError.commandFailed(command: arguments.joined(separator: " "),
                                         exitCode: result.exitCode, stderr: result.stderr)
        }
        return result
    }
}
