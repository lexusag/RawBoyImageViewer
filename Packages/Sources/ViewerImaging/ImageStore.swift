import Foundation
import RawBoyBrowseKit

/// Loads and caches screen-size previews and full-resolution images, and loads the neighbours of the current photo
/// ahead of time. Concurrent requests for the same image share one decode.
public actor ImageStore {
    public enum Kind: Hashable, Sendable {
        case preview
        case full
    }

    private struct Key: Hashable {
        let url: URL
        let kind: Kind
    }

    private var cache: LRUCache<Key, LoadedImage>
    private var inFlight: [Key: Task<LoadedImage?, Never>] = [:]
    private var prefetchTask: Task<Void, Never>?
    private var previewPixelSize: Int

    /// [budget] in bytes; [previewPixelSize] is the long edge previews are decoded to (the screen's, in pixels).
    public init(budget: Int = 1_500_000_000, previewPixelSize: Int = 3840) {
        cache = LRUCache(budget: budget)
        self.previewPixelSize = previewPixelSize
    }

    /// Changes the preview size (another screen); cached previews of another size are dropped.
    public func setPreviewPixelSize(_ size: Int) {
        guard size != previewPixelSize else { return }
        previewPixelSize = size
        cache.removeAll()
    }

    /// The cached image, without loading.
    public func cached(_ url: URL, _ kind: Kind) -> LoadedImage? {
        cache.value(for: Key(url: url, kind: kind))
    }

    /// The image, from the cache or decoded now.
    public func image(_ url: URL, _ kind: Kind) async -> LoadedImage? {
        let key = Key(url: url, kind: kind)
        if let hit = cache.value(for: key) { return hit }
        if let running = inFlight[key] { return await running.value }
        let size = previewPixelSize
        let task = Task.detached(priority: .userInitiated) { () -> LoadedImage? in
            switch kind {
            case .preview: ImageLoader.preview(of: url, maxPixelSize: size)
            case .full: ImageLoader.fullResolution(of: url)
            }
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            cache.insert(image, for: key, cost: image.cost)
        }
        return image
    }

    /// Loads previews of [urls] in order, one at a time, replacing any earlier prefetch.
    public func prefetch(_ urls: [URL]) {
        prefetchTask?.cancel()
        prefetchTask = Task(priority: .utility) {
            for url in urls {
                if Task.isCancelled { return }
                _ = await image(url, .preview)
            }
        }
    }
}
