import CoreGraphics
import Foundation
import ImageIO

/// Small images for the grid and filmstrip, through ImageIO.
public enum Thumbnailer {
    /// A thumbnail of the image at [url] whose long edge is at most [maxPixelSize], with the EXIF orientation applied.
    ///
    /// A JPEG's own EXIF thumbnail is used only when it is nearly as big as asked and has the photo's shape: cameras
    /// store 160 × 120 ones, and a portrait photo's is landscape with black bars at the sides.
    public static func thumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let size = ImageLoader.fullSize(of: url)
        if let embedded = make(source, maxPixelSize, always: false), let size,
            fits(embedded, size: (size.width, size.height), maxPixelSize: maxPixelSize)
        {
            return embedded
        }
        return make(source, maxPixelSize, always: true)
    }

    /// [image] is at least [fraction] of [maxPixelSize] (or of the photo, when smaller) and has the photo's aspect
    /// ratio.
    public static func fits(
        _ image: CGImage, size: (width: Double, height: Double), maxPixelSize: Int, fraction: Double = 0.75
    ) -> Bool {
        let wanted = min(Double(maxPixelSize), max(size.width, size.height)) * fraction
        guard Double(max(image.width, image.height)) >= wanted, size.width > 0, size.height > 0 else { return false }
        let aspect = Double(image.width) / Double(image.height)
        return abs(aspect / (size.width / size.height) - 1) < 0.03
    }

    private static func make(_ source: CGImageSource, _ maxPixelSize: Int, always: Bool) -> CGImage? {
        let options: [CFString: Any] = [
            always ? kCGImageSourceCreateThumbnailFromImageAlways : kCGImageSourceCreateThumbnailFromImageIfAbsent:
                true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
