import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import RawBoyBrowseKit
import UniformTypeIdentifiers

/// A small picture for the grid and filmstrip.
public struct Thumbnail: @unchecked Sendable {  // CGImage is immutable.
    public let cgImage: CGImage
}

/// Grid and filmstrip thumbnails: from memory, else the disk cache, else made from the file. Raws use their embedded
/// camera JPEG when it is at least `minEmbedded` px (RawBoy Browser's rule for its grid), else ImageIO decodes them.
public actor ThumbnailStore {
    private var cache: LRUCache<URL, Thumbnail>
    private var inFlight: [URL: Task<Thumbnail?, Never>] = [:]
    public let pixelSize: Int
    private let disk: DiskThumbnailCache?

    /// RawBoy Browser's grid uses the smallest preview of at least 400 px.
    public static let minEmbedded = 400

    public init(pixelSize: Int = 320, budget: Int = 256_000_000, disk: DiskThumbnailCache? = .shared) {
        self.pixelSize = pixelSize
        self.disk = disk
        cache = LRUCache(budget: budget)
    }

    /// The thumbnail of [url]; nil when it can't be read. [modified] and [size] key the disk cache.
    public func thumbnail(_ url: URL, size: Int64? = nil, modified: Date? = nil) async -> Thumbnail? {
        if let hit = cache.value(for: url) { return hit }
        if let running = inFlight[url] { return await running.value }
        let pixels = pixelSize
        let disk = disk
        let task = Task.detached(priority: .utility) { () -> Thumbnail? in
            // Without them the disk cache couldn't tell a changed file: read them (metadata only).
            var size = size
            var modified = modified
            if size == nil || modified == nil {
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                size = size ?? values?.fileSize.map(Int64.init)
                modified = modified ?? values?.contentModificationDate
            }
            let key = disk?.key(url: url, size: size, modified: modified, pixels: pixels)
            if let key, let image = disk?.read(key) { return Thumbnail(cgImage: image) }
            guard let made = Self.make(url, pixels) else { return nil }
            if let key { disk?.write(made, key) }
            return Thumbnail(cgImage: made)
        }
        inFlight[url] = task
        let thumb = await task.value
        inFlight[url] = nil
        if let thumb {
            cache.insert(thumb, for: url, cost: thumb.cgImage.bytesPerRow * thumb.cgImage.height)
        }
        return thumb
    }

    static func make(_ url: URL, _ pixels: Int) -> CGImage? {
        if PhotoFileType(fileName: url.lastPathComponent) == .raw, let image = embedded(url, pixels) {
            return ImageLoader.displayReady(image)
        }
        return Thumbnailer.thumbnail(at: url, maxPixelSize: pixels).map(ImageLoader.displayReady)
    }

    /// The raw's embedded camera JPEG, scaled down, when it is big enough.
    static func embedded(_ url: URL, _ pixels: Int) -> CGImage? {
        guard let source = FileSource(url: url), let preview = EmbeddedPreviews.find(in: source),
            max(preview.width, preview.height) >= minEmbedded
        else { return nil }
        return EmbeddedJPEG.decode(preview.jpeg(from: source), maxPixelSize: pixels)
    }
}

/// Decoding the bytes of an embedded JPEG (orientation applied).
public enum EmbeddedJPEG {
    public static func decode(_ bytes: [UInt8], maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(Data(bytes) as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Thumbnails on disk (`~/Library/Caches/RawBoy Viewer/Thumbnails`), as JPEG, keyed by the file's path, size and
/// modified date, so a changed file gets a new one. Trimmed to [limit] bytes, oldest first.
public final class DiskThumbnailCache: Sendable {
    public static let shared: DiskThumbnailCache? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return DiskThumbnailCache(folder: caches.appendingPathComponent("RawBoy Viewer/Thumbnails"))
    }()

    public let folder: URL
    public let limit: Int64

    public init(folder: URL, limit: Int64 = 1_000_000_000) {
        self.folder = folder
        self.limit = limit
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    public func key(url: URL, size: Int64?, modified: Date?, pixels: Int) -> String {
        // v2: thumbnails made from letterboxed EXIF thumbnails before Thumbnailer.fits are never read again.
        let text = "v2|\(url.standardizedFileURL.path)|\(size ?? -1)|\(modified?.timeIntervalSince1970 ?? -1)|\(pixels)"
        return SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private func file(_ key: String) -> URL { folder.appendingPathComponent(key + ".jpg") }

    public func read(_ key: String) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file(key) as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(
                source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        return ImageLoader.displayReady(image)
    }

    public func write(_ image: CGImage, _ key: String) {
        let url = file(key)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    /// Deletes the least recently modified thumbnails until the cache is within its limit.
    public func trim() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)
        else { return }
        var entries = files.compactMap { url -> (URL, Int64, Date)? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, Int64(v.fileSize ?? 0), v.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.1 }
        guard total > limit else { return }
        entries.sort { $0.2 < $1.2 }
        for (url, size, _) in entries where total > limit {
            try? FileManager.default.removeItem(at: url)
            total -= size
        }
    }
}
