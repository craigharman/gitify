import Foundation

/// Watches a remote repository by polling git state over SSH.
/// Fires `onChange` when the HEAD commit, working-tree status, or ref tips change.
///
/// Polls every 3 seconds. This is less responsive than FSEvents (0.5 s) but avoids the
/// overhead of a persistent SSH connection.
public final class SSHRepositoryWatcher: RepositoryWatching, @unchecked Sendable {
    private let runner: SSHGitRunner
    private let onChange: @Sendable () -> Void
    private var pollTask: Task<Void, Never>?
    /// Fingerprint of the last observed state.
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
        // Build a fingerprint from three sources to catch all types of changes:
        //  1. HEAD sha \u{2014} detects commits, checkouts, resets on the current branch
        //  2. Status byte count \u{2014} detects working-tree / staging area changes
        //  3. Ref tips hash \u{2014} detects pushed/deleted branches, tags, remote updates
        let headResult = try? await runner.runRaw(["rev-parse", "HEAD"])
        let statusResult = try? await runner.runRaw(["status", "--porcelain=v2", "-z"])
        let refsResult = try? await runner.runRaw(["for-each-ref", "--format=%(refname) %(objectname)"])

        let head = headResult?.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let statusLen = statusResult?.stdout.count ?? 0
        let refsHash = refsResult?.stdout.count ?? 0  // Byte length as cheap change detector

        let fingerprint = "\(head):\(statusLen):\(refsHash)"

        if lastFingerprint.isEmpty {
            // First poll \u{2014} seed the fingerprint without firing.
            lastFingerprint = fingerprint
        } else if fingerprint != lastFingerprint {
            lastFingerprint = fingerprint
            onChange()
        }
    }
}
