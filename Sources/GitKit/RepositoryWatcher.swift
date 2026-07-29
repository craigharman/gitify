import Foundation

/// Common interface for local (FSEvents) and remote (SSH polling) repository watchers.
public protocol RepositoryWatching: AnyObject, Sendable {
    func start()
    func stop()
}

/// Watches a repository's working tree (and its `.git` directory) with FSEvents, invoking
/// `onChange` when anything changes on disk. Events are coalesced by FSEvents' latency
/// window; callers should debounce further before doing expensive work.
public final class RepositoryWatcher: RepositoryWatching, @unchecked Sendable {
    private let path: String
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.gitify.repository-watcher", qos: .utility)
    private var stream: FSEventStreamRef?

    public init(root: URL, onChange: @escaping @Sendable () -> Void) {
        self.path = root.path
        self.onChange = onChange
    }

    public func start() {
        queue.async { [weak self] in
            guard let self, self.stream == nil else { return }

            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil, release: nil, copyDescription: nil)

            // C callback can't capture Swift state, so we route through the context's `info`.
            let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<RepositoryWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
            }

            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault, callback, &context,
                [self.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.5, // latency (s): coalesce bursts
                UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer))
            else { return }

            FSEventStreamSetDispatchQueue(stream, self.queue)
            FSEventStreamStart(stream)
            self.stream = stream
        }
    }

    public func stop() {
        // Must run on the stream's dispatch queue so no callback is in-flight when we
        // invalidate. Uses sync so the caller can safely release the watcher afterward.
        queue.sync {
            guard let stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    deinit {
        // If stop() was already called, stream is nil and this is a no-op.
        // Otherwise, schedule cleanup on the stream's queue. We can't use queue.sync
        // from deinit (risks deadlock), so capture the values and dispatch async.
        guard let stream else { return }
        let q = queue
        // OpaquePointer is not Sendable but FSEventStreamRef is safe to pass across queues.
        nonisolated(unsafe) let s = stream
        q.async {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
        }
    }
}
