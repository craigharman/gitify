import Foundation

/// Mutable storage shared across pipe-reading dispatch closures. Access is synchronized
/// by the surrounding `DispatchGroup`, so `@unchecked Sendable` is sound.
private final class SSHCaptureBox: @unchecked Sendable {
    var stdout = Data()
    var stderr = Data()
    var stderrText = ""
}

/// Executes git commands on a remote server over SSH.
///
/// Drop-in replacement for `GitRunner` that wraps every git invocation in
/// `ssh user@host git -C /path <args>`. The user\u{2019}s SSH config, agent, and keys
/// handle authentication transparently.
///
/// Like `GitRunner`, the actor serialises invocations to prevent `index.lock` contention
/// on the remote repository.
public actor SSHGitRunner: GitRunnerProtocol {
    public let workingDirectory: URL?
    public let remotePath: String
    private let host: String
    private let user: String
    private let port: Int
    private let sshURL: URL

    public init(host: String, user: String = "git", port: Int = 22, remotePath: String) {
        self.host = host
        self.user = user
        self.port = port
        self.remotePath = remotePath
        // Synthetic URL for identity/display purposes only.
        self.workingDirectory = URL(fileURLWithPath: remotePath)
        self.sshURL = URL(fileURLWithPath: SSHGitRunner.sshPath)
    }

    private static let sshPath: String = {
        let candidates = ["/usr/bin/ssh", "/opt/homebrew/bin/ssh", "/usr/local/bin/ssh"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/usr/bin/ssh"
    }()

    /// Builds the SSH arguments for running a git command remotely.
    ///
    /// The remote command is constructed as a single shell string so that git format
    /// strings containing control characters (\u{1f}, \u{1e}) survive the SSH transport.
    /// Environment variables are set via `env` to match the local `GitRunner` behaviour.
    private func sshArgs(gitArguments: [String]) -> [String] {
        let quotedPath = shellQuote(remotePath)
        let quotedGitArgs = gitArguments.map { shellQuote($0) }.joined(separator: " ")
        let remoteCommand = "LC_ALL=C GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 GIT_EDITOR=true GIT_ALLOW_PROTOCOL=https:http:ssh:git:file git -C \(quotedPath) \(quotedGitArgs)"

        return [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=accept-new",
            "-p", String(port),
            "-l", user,
            host,
            remoteCommand,
        ]
    }

    public func runRaw(_ arguments: [String]) async throws -> GitProcessResult {
        let sshURL = self.sshURL
        let args = sshArgs(gitArguments: arguments)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = sshURL
                process.arguments = args

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let box = SSHCaptureBox()
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
                        "SSH connection failed: \(error.localizedDescription)"))
                    return
                }

                process.waitUntilExit()
                group.wait()

                continuation.resume(returning: GitProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: box.stdout,
                    stderr: String(decoding: box.stderr, as: UTF8.self)
                ))
            }
        }
    }

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

    public func runString(_ arguments: [String]) async throws -> String {
        String(decoding: try await run(arguments), as: UTF8.self)
    }

    @discardableResult
    public func runStreaming(
        _ arguments: [String],
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> GitProcessResult {
        let sshURL = self.sshURL
        let args = sshArgs(gitArguments: arguments)

        let result: GitProcessResult = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = sshURL
                process.arguments = args

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let box = SSHCaptureBox()
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
                        "SSH connection failed: \(error.localizedDescription)"))
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

    /// Shell-quotes a string for safe inclusion in the remote command.
    /// Preserves tilde expansion for paths starting with `~/` or bare `~`.
    private func shellQuote(_ string: String) -> String {
        if string == "~" { return "~" }
        if string.hasPrefix("~/") {
            return "~/" + singleQuote(String(string.dropFirst(2)))
        }
        return singleQuote(string)
    }

    private func singleQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
