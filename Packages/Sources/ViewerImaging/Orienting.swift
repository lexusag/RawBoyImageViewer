import CoreGraphics
import RawBoyBrowseKit

/// Turning and mirroring decoded pictures (a rotation kept in a sidecar, on top of the file's own orientation).
public enum Orienting {
    /// [image] mirrored and turned as [orientation] says.
    public static func apply(_ orientation: Orientation, to image: CGImage) -> CGImage {
        guard orientation != .up else { return image }
        let w = image.width
        let h = image.height
        let (outW, outH) = orientation.isQuarterTurned ? (h, w) : (w, h)
        guard
            let context = CGContext(
                data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                space: image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
                    ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: ImageLoader.displayBitmapInfo.rawValue)
        else { return image }
        // Core Graphics is y-up: a clockwise turn on screen is a negative angle here.
        context.translateBy(x: Double(outW) / 2, y: Double(outH) / 2)
        context.rotate(by: -Double(orientation.quarterTurns) * .pi / 2)
        if orientation.mirrored { context.scaleBy(x: -1, y: 1) }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: -Double(w) / 2, y: -Double(h) / 2, width: Double(w), height: Double(h)))
        return context.makeImage() ?? image
    }

    /// What must be done to a picture ImageIO already turned upright by [fileOrientation] so it shows as [wanted].
    public static func delta(from fileOrientation: Int, to wanted: Int) -> Orientation {
        Orientation(exif: fileOrientation).inverse.then(Orientation(exif: wanted))
    }
}
