import Foundation
import RawBoyBrowseKit

/// Loads and caches screen-size previews and full-resolution images, and loads the neighbours of the current photo
/// ahead of time. Concurrent requests for the same image share one decode.
public actor ImageStore {
    public enum Kind: Hashable, Sendable {
        case preview
        case full
        /// A raw developed by macOS at screen size ("real preview").
        case developed
        /// The same at full size (1:1).
        case developedFull
    }

    private struct Key: Hashable {
        let url: URL
        let kind: Kind
        /// A sidecar's orientation, nil when it sets none.
        let orientation: Int?
    }

    private var cache: LRUCache<Key, LoadedImage>
    private var inFlight: [Key: Task<LoadedImage?, Never>] = [:]
    private var prefetchTask: Task<Void, Never>?
    private var previewPixelSize: Int
    private let realPreview: any RealPreviewProvider

    /// [budget] in bytes; [previewPixelSize] is the long edge previews are decoded to (the screen's, in pixels);
    /// [realPreview] develops the raws of `.developed` and `.developedFull`.
    public init(
        budget: Int = 1_500_000_000, previewPixelSize: Int = 3840,
        realPreview: any RealPreviewProvider = CoreImageRealPreview()
    ) {
        cache = LRUCache(budget: budget)
        self.previewPixelSize = previewPixelSize
        self.realPreview = realPreview
    }

    /// Changes the preview size (another screen); cached previews of another size are dropped.
    public func setPreviewPixelSize(_ size: Int) {
        guard size != previewPixelSize else { return }
        previewPixelSize = size
        cache.removeAll()
    }

    /// The cached image, without loading.
    public func cached(_ url: URL, _ kind: Kind, orientation: Int? = nil) -> LoadedImage? {
        cache.value(for: Key(url: url, kind: kind, orientation: orientation))
    }

    /// The image, from the cache or decoded now, turned to [orientation] when a sidecar sets one.
    public func image(_ url: URL, _ kind: Kind, orientation: Int? = nil) async -> LoadedImage? {
        let key = Key(url: url, kind: kind, orientation: orientation)
        if let hit = cache.value(for: key) { return hit }
        if let running = inFlight[key] { return await running.value }
        let size = previewPixelSize
        let realPreview = realPreview
        let task = Task.detached(priority: .userInitiated) { () -> LoadedImage? in
            switch kind {
            case .preview: ImageLoader.preview(of: url, maxPixelSize: size, orientation: orientation)
            case .full: ImageLoader.fullResolution(of: url, orientation: orientation)
            case .developed: realPreview.develop(url, maxPixelSize: size, orientation: orientation)
            case .developedFull: realPreview.develop(url, maxPixelSize: nil, orientation: orientation)
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

    /// Drops every cached picture of [url] (the file changed).
    public func forget(_ url: URL) {
        for kind in [Kind.preview, .full, .developed, .developedFull] {
            for orientation in [nil] + (1...8).map(Optional.some) {
                cache.remove(Key(url: url, kind: kind, orientation: orientation))
            }
        }
    }

    /// Loads previews of [items] in order, one at a time, replacing any earlier prefetch.
    public func prefetch(_ items: [(url: URL, orientation: Int?)], kind: Kind = .preview) {
        prefetchTask?.cancel()
        prefetchTask = Task(priority: .utility) {
            for item in items {
                if Task.isCancelled { return }
                _ = await image(item.url, kind, orientation: item.orientation)
            }
        }
    }
}
