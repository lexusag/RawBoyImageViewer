import CoreGraphics
import Foundation
import ImageIO
import RawBoyBrowseKit

/// A decoded picture, ready to show.
public struct LoadedImage: @unchecked Sendable {  // CGImage is immutable.
    public let cgImage: CGImage
    /// The photo's full size in pixels, upright (EXIF orientation applied), whatever size [cgImage] is.
    public let fullSize: Size2D
    /// [cgImage] has every pixel of the photo (1:1 shows real pixels, not an enlarged preview).
    public let isFullResolution: Bool

    public var cost: Int { cgImage.bytesPerRow * cgImage.height }
}

/// Decodes photos through ImageIO. Embedded camera previews are used when they are large enough; RawBoy's own
/// preview parser and RAW engine replace parts of this later (PLAN.md §4).
public enum ImageLoader {
    /// A raw's embedded preview is good enough for the screen once its long edge reaches this (RawBoy Browser's rule:
    /// the viewer takes the smallest preview of at least 2560 px).
    public static let minEmbeddedPreview = 2560

    /// The photo's upright size in pixels, or nil when ImageIO can't read it.
    public static func fullSize(of url: URL) -> Size2D? {
        guard let source = makeSource(url) else { return nil }
        return fullSize(of: source)
    }

    /// A screen-size image: its long edge is at most [maxPixelSize], and at least [minEmbeddedPreview] or the
    /// photo's size when an embedded preview is used. Raws use the camera's JPEG that RawBoy's parser finds
    /// (`EmbeddedPreviews`, so RawBoy Browser and the viewer show the same picture), else ImageIO's.
    public static func preview(of url: URL, maxPixelSize: Int) -> LoadedImage? {
        guard let source = makeSource(url), let size = fullSize(of: source) else { return nil }
        let longEdge = Int(max(size.width, size.height))
        let target = min(maxPixelSize, longEdge)
        let wanted = min(target, minEmbeddedPreview)

        if PhotoFileType(fileName: url.lastPathComponent) == .raw, let bytes = FileSource(url: url),
            let embedded = EmbeddedPreviews.find(in: bytes), max(embedded.width, embedded.height) >= wanted,
            let image = EmbeddedJPEG.decode(embedded.jpeg(from: bytes), maxPixelSize: target)
        {
            return LoadedImage(cgImage: displayReady(image), fullSize: size, isFullResolution: isFull(image, size))
        }

        if let embedded = thumbnail(source, maxPixelSize: target, always: false),
            max(embedded.width, embedded.height) >= wanted
        {
            return LoadedImage(
                cgImage: displayReady(embedded), fullSize: size, isFullResolution: isFull(embedded, size))
        }
        guard let decoded = thumbnail(source, maxPixelSize: target, always: true) else { return nil }
        return LoadedImage(cgImage: displayReady(decoded), fullSize: size, isFullResolution: isFull(decoded, size))
    }

    /// Every pixel of the photo, upright. Slow for raws.
    public static func fullResolution(of url: URL) -> LoadedImage? {
        guard let source = makeSource(url), let size = fullSize(of: source) else { return nil }
        guard let image = thumbnail(source, maxPixelSize: Int(max(size.width, size.height)), always: true) else {
            return nil
        }
        return LoadedImage(cgImage: displayReady(image), fullSize: size, isFullResolution: true)
    }

    /// The pixel layout Core Animation shows without converting: 8-bit BGRA, premultiplied.
    public static let displayBitmapInfo = CGBitmapInfo(
        rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

    /// [image] redrawn as 8-bit BGRA in its own colour space (Display P3 for extended-range or non-RGB images), so
    /// showing it costs the main thread nothing. Raws render as 16-bit P3, which took Core Animation ~100 ms per photo
    /// to convert on the main thread. Call it off the main thread.
    public static func displayReady(_ image: CGImage) -> CGImage {
        let space: CGColorSpace =
            if let own = image.colorSpace, own.model == .rgb, !CGColorSpaceUsesExtendedRange(own) {
                own
            } else {
                CGColorSpace(name: CGColorSpace.displayP3)!
            }
        if image.bitsPerComponent == 8, image.bitsPerPixel == 32, image.bitmapInfo == displayBitmapInfo,
            image.colorSpace == space
        {
            return image
        }
        guard
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: displayBitmapInfo.rawValue)
        else { return image }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }

    private static func makeSource(_ url: URL) -> CGImageSource? {
        CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
    }

    private static func fullSize(of source: CGImageSource) -> Size2D? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { return nil }
        // Orientations 5-8 turn the photo a quarter.
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5
            ? Size2D(width: Double(height), height: Double(width))
            : Size2D(width: Double(width), height: Double(height))
    }

    private static func thumbnail(_ source: CGImageSource, maxPixelSize: Int, always: Bool) -> CGImage? {
        let options: [CFString: Any] = [
            always ? kCGImageSourceCreateThumbnailFromImageAlways : kCGImageSourceCreateThumbnailFromImageIfAbsent:
                true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func isFull(_ image: CGImage, _ size: Size2D) -> Bool {
        Double(max(image.width, image.height)) >= max(size.width, size.height)
    }
}
