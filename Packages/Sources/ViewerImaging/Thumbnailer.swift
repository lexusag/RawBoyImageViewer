import CoreGraphics
import Foundation
import ImageIO

/// Small images for the grid and filmstrip, through ImageIO.
public enum Thumbnailer {
    /// A thumbnail of the image at [url] whose long edge is at most [maxPixelSize], with the EXIF orientation applied.
    /// Uses the file's embedded preview when it has one that is large enough, else decodes the image.
    public static func thumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
