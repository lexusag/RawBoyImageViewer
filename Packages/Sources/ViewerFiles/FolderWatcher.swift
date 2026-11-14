import CoreServices
import Foundation

/// Tells when files in one folder (not its subfolders) appear, go, are renamed or change, through FSEvents. Changes
/// arrive together after [latency] seconds, on the main queue, as file names; hidden files (atomic writes' temporary
/// files among them) are left out.
public final class FolderWatcher: @unchecked Sendable {  // FSEventStream is only touched on its queue and in deinit.
    public struct Change: Equatable, Sendable {
        /// Files that appeared, went or were renamed: the folder's contents changed.
        public var structural: Set<String> = []
        /// Files whose contents changed.
        public var modified: Set<String> = []

        public var isEmpty: Bool { structural.isEmpty && modified.isEmpty }
    }

    public let folder: URL
    private var stream: FSEventStreamRef?
    private let onChange: @MainActor (Change) -> Void

    public init?(folder: URL, latency: Double = 0.3, onChange: @escaping @MainActor (Change) -> Void) {
        self.folder = folder.standardizedFileURL
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let names = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            watcher.received(names, Array(UnsafeBufferPointer(start: flags, count: count)))
        }
        guard
            let stream = FSEventStreamCreate(
                nil, callback, &context, [self.folder.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
                FSEventStreamCreateFlags(
                    kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                        | kFSEventStreamCreateFlagNoDefer))
        else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    private func received(_ paths: [String], _ flags: [FSEventStreamEventFlags]) {
        var change = Change()
        let structural = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved
                | kFSEventStreamEventFlagItemRenamed)
        let modified = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemInodeMetaMod)
        for (path, flag) in zip(paths, flags) {
            let url = URL(fileURLWithPath: path)
            // This folder's own files only: not subfolders' contents, not hidden (temporary) files.
            guard url.deletingLastPathComponent().standardizedFileURL.path == folder.path else { continue }
            let name = url.lastPathComponent
            guard !name.hasPrefix(".") else { continue }
            if flag & structural != 0 {
                change.structural.insert(name)
            } else if flag & modified != 0 {
                change.modified.insert(name)
            }
        }
        guard !change.isEmpty else { return }
        MainActor.assumeIsolated { onChange(change) }
    }
}
