import CoreGraphics
import Foundation
import RawBoyBrowseKit

/// A small picture for the filmstrip and grid.
public struct Thumbnail: @unchecked Sendable {  // CGImage is immutable.
    public let cgImage: CGImage
}

/// Filmstrip and grid thumbnails from the files' embedded previews, cached in memory. A disk cache comes with the
/// browser (M3).
public actor ThumbnailStore {
    private var cache: LRUCache<URL, Thumbnail>
    private var inFlight: [URL: Task<Thumbnail?, Never>] = [:]
    public let pixelSize: Int

    public init(pixelSize: Int = 320, budget: Int = 256_000_000) {
        self.pixelSize = pixelSize
        cache = LRUCache(budget: budget)
    }

    public func thumbnail(_ url: URL) async -> Thumbnail? {
        if let hit = cache.value(for: url) { return hit }
        if let running = inFlight[url] { return await running.value }
        let size = pixelSize
        let task = Task.detached(priority: .utility) { () -> Thumbnail? in
            Thumbnailer.thumbnail(at: url, maxPixelSize: size).map { Thumbnail(cgImage: ImageLoader.displayReady($0)) }
        }
        inFlight[url] = task
        let thumb = await task.value
        inFlight[url] = nil
        if let thumb {
            cache.insert(thumb, for: url, cost: thumb.cgImage.bytesPerRow * thumb.cgImage.height)
        }
        return thumb
    }
}
