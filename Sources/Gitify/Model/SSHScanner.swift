import Foundation

/// Runs SSH commands to test connectivity and discover repositories on a remote server.
/// For local servers (localhost/127.0.0.1), commands run directly without SSH.
///
/// Uses the user\u{2019}s installed `ssh` binary and their `~/.ssh/config`, agent, and keys.
/// All commands run with `BatchMode=yes` (no interactive prompts) and `ConnectTimeout=5`
/// to avoid hanging when keys are missing or the host is unreachable.
enum SSHScanner {

    /// Tests whether an SSH connection can be established.
    /// Returns `nil` on success, or an error description on failure.
    static func testConnection(_ server: SSHServer) async -> String? {
        if isLocal(server) { return nil }
        do {
            let result = try await runSSH(server: server, remoteCommand: "echo ok")
            if result.exitCode == 0 { return nil }
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return stderr.isEmpty ? "Connection failed (exit code \(result.exitCode))." : stderr
        } catch {
            return error.localizedDescription
        }
    }

    /// Discovers git repositories under the server\u{2019}s configured base path.
    ///
    /// Finds non-bare repos (directories containing a `.git` subdirectory) and bare repos
    /// (directories ending in `.git` that contain a `HEAD` file). Returns the list sorted
    /// by path.
    static func discoverRepositories(_ server: SSHServer) async throws -> [SSHRepo] {
        let basePath = server.basePath.isEmpty ? "~" : server.basePath
        // Two-pronged search:
        //  1. Non-bare repos: find directories named ".git" (working-tree repos).
        //  2. Bare repos: find directories whose name ends in ".git" (but isn\u{2019}t exactly ".git")
        //     that contain a HEAD file.
        let command = "{ find \(shellQuote(basePath)) -maxdepth 3 -type d -name .git 2>/dev/null; find \(shellQuote(basePath)) -maxdepth 3 -type d -name '*.git' ! -name .git 2>/dev/null; } | head -200"

        let result: ProcessResult
        if isLocal(server) {
            result = try await runLocal(command: command)
        } else {
            result = try await runSSH(server: server, remoteCommand: command)
        }

        if result.exitCode != 0 && result.exitCode != 1 {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SSHScannerError.scanFailed(stderr.isEmpty ? "Scan failed (exit code \(result.exitCode))." : stderr)
        }

        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stdout.isEmpty else { return [] }

        var repos: [SSHRepo] = []
        for line in stdout.components(separatedBy: "\n") {
            let path = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { continue }

            // A ".git" directory means the parent is a non-bare working tree.
            // A "something.git" directory is a bare repo.
            let effectivePath: String
            if (path as NSString).lastPathComponent == ".git" {
                effectivePath = (path as NSString).deletingLastPathComponent
            } else {
                effectivePath = path
            }

            let name = displayName(for: effectivePath)
            let cloneURL = buildCloneURL(server: server, remotePath: effectivePath)
            repos.append(SSHRepo(path: effectivePath, name: name, cloneURL: cloneURL))
        }

        // Deduplicate and sort.
        var seen = Set<String>()
        repos = repos.filter { seen.insert($0.path).inserted }
        repos.sort { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        return repos
    }

    // MARK: - Private

    private struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    /// Mutable storage shared across pipe-reading dispatch closures. Access is synchronized
    /// by the surrounding `DispatchGroup`, so `@unchecked Sendable` is sound.
    private final class CaptureBox: @unchecked Sendable {
        var stdout = Data()
        var stderr = Data()
    }

    /// Whether the server points to the local machine.
    private static func isLocal(_ server: SSHServer) -> Bool {
        let host = server.host.lowercased()
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    /// Runs a shell command locally via `/bin/sh -c`.
    private static func runLocal(command: String) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", command]

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
                    continuation.resume(throwing: SSHScannerError.sshUnavailable(error.localizedDescription))
                    return
                }

                process.waitUntilExit()
                group.wait()

                continuation.resume(returning: ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: String(decoding: box.stdout, as: UTF8.self),
                    stderr: String(decoding: box.stderr, as: UTF8.self)
                ))
            }
        }
    }

    /// Runs an SSH command against the given server.
    private static func runSSH(server: SSHServer, remoteCommand: String) async throws -> ProcessResult {
        let sshPath = sshExecutablePath()
        // Validate arguments against injection.
        for value in [server.host, server.user] {
            guard !value.hasPrefix("-") else {
                throw SSHScannerError.invalidArgument("\(value) may not begin with \u{201c}-\u{201d}.")
            }
        }
        guard server.port > 0, server.port <= 65535 else {
            throw SSHScannerError.invalidArgument("Port must be between 1 and 65535.")
        }

        let args = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            "-o", "StrictHostKeyChecking=accept-new",
            "-p", String(server.port),
            "-l", server.user,
            server.host,
            remoteCommand,
        ]

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: sshPath)
                process.arguments = args

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
                    continuation.resume(throwing: SSHScannerError.sshUnavailable(error.localizedDescription))
                    return
                }

                process.waitUntilExit()
                group.wait()

                continuation.resume(returning: ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: String(decoding: box.stdout, as: UTF8.self),
                    stderr: String(decoding: box.stderr, as: UTF8.self)
                ))
            }
        }
    }

    /// Best-effort discovery of the `ssh` binary.
    private static func sshExecutablePath() -> String {
        let candidates = ["/usr/bin/ssh", "/opt/homebrew/bin/ssh", "/usr/local/bin/ssh"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return "/usr/bin/ssh"
    }

    /// Derives a display name from a remote path (e.g. \u{201c}/srv/git/project.git\u{201d} \u{2192} \u{201c}project\u{201d}).
    private static func displayName(for path: String) -> String {
        var name = (path as NSString).lastPathComponent
        if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
        return name.isEmpty ? path : name
    }

    /// Builds a clone URL for the given server and remote path.
    /// Local servers return a file path; remote servers return an SSH URL.
    private static func buildCloneURL(server: SSHServer, remotePath: String) -> String {
        if isLocal(server) { return remotePath }
        if server.port == 22 {
            return "\(server.user)@\(server.host):\(remotePath)"
        }
        return "ssh://\(server.user)@\(server.host):\(server.port)\(remotePath)"
    }

    /// Shell-quotes a string for safe inclusion in a shell command.
    /// Preserves tilde expansion for paths starting with `~/` or bare `~`.
    private static func shellQuote(_ string: String) -> String {
        if string == "~" { return "~" }
        if string.hasPrefix("~/") {
            return "~/" + singleQuote(String(string.dropFirst(2)))
        }
        return singleQuote(string)
    }

    private static func singleQuote(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum SSHScannerError: LocalizedError {
    case sshUnavailable(String)
    case scanFailed(String)
    case invalidArgument(String)

    var errorDescription: String? {
        switch self {
        case .sshUnavailable(let detail): "SSH is not available: \(detail)"
        case .scanFailed(let detail): detail
        case .invalidArgument(let detail): detail
        }
    }
}
