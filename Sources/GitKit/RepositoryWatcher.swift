import Foundation

/// Watches a repository's working tree (and its `.git` directory) with FSEvents, invoking
/// `onChange` when anything changes on disk. Events are coalesced by FSEvents' latency
/// window; callers should debounce further before doing expensive work.
public final class RepositoryWatcher: @unchecked Sendable {
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
        queue.async { [weak self] in
            guard let self, let stream = self.stream else { return }
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
