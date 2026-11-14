import CoreImage
import Foundation
import RawBoyBrowseKit

/// A raw developed from its sensor data by macOS (Core Image's RAW filter, as shot), instead of the camera's embedded
/// JPEG: what "real preview" shows. Not RawBoy's look: that needs RawBoy's own engine (PLAN.md §4, phase 2).
public enum RawDeveloper {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// The raw at [url] developed as shot, its long edge at most [maxPixelSize] (nil: full size), turned as
    /// [orientation] says when a sidecar sets one. Nil when it isn't a raw Core Image can develop.
    public static func develop(_ url: URL, maxPixelSize: Int?, orientation: Int? = nil) -> LoadedImage? {
        // Core Image's RAW filter opens other images too: only raws are "developed".
        guard PhotoFileType(fileName: url.lastPathComponent) == .raw, let filter = CIRAWFilter(imageURL: url),
            let size = ImageLoader.fullSize(of: url)
        else { return nil }
        let longEdge = max(size.width, size.height)
        if let maxPixelSize {
            // Developing at a lower scale is much quicker than developing in full and scaling down.
            filter.scaleFactor = Float(min(1, Double(maxPixelSize) / longEdge))
        }
        guard let output = filter.outputImage,
            let p3 = CGColorSpace(name: CGColorSpace.displayP3),
            let cg = context.createCGImage(output, from: output.extent, format: .RGBA8, colorSpace: p3)
        else { return nil }
        let developed = LoadedImage(
            cgImage: ImageLoader.displayReady(cg), fullSize: size, isFullResolution: maxPixelSize == nil)
        return ImageLoader.oriented(developed, url: url, orientation: orientation)
    }
}
