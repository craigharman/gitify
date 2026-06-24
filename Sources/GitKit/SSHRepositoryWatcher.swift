import Foundation

/// Watches a remote repository by polling `git rev-parse HEAD` and `git status` over SSH.
/// Fires `onChange` when the HEAD commit or working-tree status changes.
///
/// Polls every 3 seconds. This is less responsive than FSEvents (0.5 s) but avoids the
/// overhead of a persistent SSH connection.
public final class SSHRepositoryWatcher: RepositoryWatching, @unchecked Sendable {
    private let runner: SSHGitRunner
    private let onChange: @Sendable () -> Void
    private var pollTask: Task<Void, Never>?
    /// Fingerprint of the last observed state (HEAD sha + status hash).
    private var lastFingerprint = ""

    public init(host: String, user: String, port: Int, remotePath: String,
                onChange: @escaping @Sendable () -> Void) {
        self.runner = SSHGitRunner(host: host, user: user, port: port, remotePath: remotePath)
        self.onChange = onChange
    }

    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                await self?.poll()
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    deinit {
        pollTask?.cancel()
    }

    private func poll() async {
        // Build a fingerprint from HEAD sha and the byte-length of porcelain status output.
        // This is cheap and avoids transferring full status over the network.
        let headResult = try? await runner.runRaw(["rev-parse", "HEAD"])
        let statusResult = try? await runner.runRaw(["status", "--porcelain=v2", "-z"])

        let head = headResult?.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let statusLen = statusResult?.stdout.count ?? 0
        let fingerprint = "\(head):\(statusLen)"

        if lastFingerprint.isEmpty {
            // First poll \u{2014} seed the fingerprint without firing.
            lastFingerprint = fingerprint
        } else if fingerprint != lastFingerprint {
            lastFingerprint = fingerprint
            onChange()
        }
    }
}
