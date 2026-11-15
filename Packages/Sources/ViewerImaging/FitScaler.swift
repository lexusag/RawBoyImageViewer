import CoreGraphics
import CoreImage
import Foundation

/// A picture made for one size on screen (see [FitScaler]).
public struct FitImage: @unchecked Sendable {  // CGImage is immutable.
    public let cgImage: CGImage
}

/// Resamples a photo to the exact number of device pixels it takes at fit, with a Lanczos-3 filter and a light
/// luminance sharpen. Core Animation's own filters blur a non-integer downscale (trilinear most of all), so the viewer
/// shows this picture pixel for pixel instead. Call it off the main thread.
public enum FitScaler {
    /// The sharpen after the downscale (Core Image's `CISharpenLuminance` amount; 0 = none). Light on purpose: more
    /// puts halos on edges.
    public static let sharpness: Float = 0.3
    /// The sharpen's radius in pixels.
    public static let sharpenRadius: Float = 0.8

    // CIContext is documented as thread safe.
    nonisolated(unsafe) private static let context = CIContext(options: [.cacheIntermediates: false])

    /// The part [region] (fractions of [image], origin bottom-left like a layer's `contentsRect`) of [image] at
    /// [width] × [height] pixels, in the image's own colour space; nil when Core Image can't.
    public static func scale(
        _ image: LoadedImage, region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1), width: Int, height: Int,
        sharpness: Float = FitScaler.sharpness
    ) -> FitImage? {
        let source = image.cgImage
        let w = Double(source.width)
        let h = Double(source.height)
        let area = CGRect(
            x: (region.minX * w).rounded(), y: (region.minY * h).rounded(),
            width: (region.width * w).rounded(), height: (region.height * h).rounded()
        ).intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard area.width >= 1, area.height >= 1, width > 0, height > 0 else { return nil }

        // The region at the origin, its edges repeated outward so the filter's reach doesn't darken the borders.
        let part = CIImage(cgImage: source).cropped(to: area)
            .transformed(by: CGAffineTransform(translationX: -area.minX, y: -area.minY))
            .clampedToExtent()
        let scaleY = Double(height) / area.height
        let scaleX = Double(width) / area.width
        guard let lanczos = CIFilter(name: "CILanczosScaleTransform") else { return nil }
        lanczos.setValue(part, forKey: kCIInputImageKey)
        lanczos.setValue(scaleY, forKey: kCIInputScaleKey)
        lanczos.setValue(scaleX / scaleY, forKey: kCIInputAspectRatioKey)
        let target = CGRect(x: 0, y: 0, width: width, height: height)
        guard var out = lanczos.outputImage?.cropped(to: target) else { return nil }

        if sharpness > 0, let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setValue(out, forKey: kCIInputImageKey)
            sharpen.setValue(sharpness, forKey: kCIInputSharpnessKey)
            sharpen.setValue(sharpenRadius, forKey: kCIInputRadiusKey)
            if let sharpened = sharpen.outputImage?.cropped(to: target) { out = sharpened }
        }

        let space: CGColorSpace =
            if let own = source.colorSpace, own.model == .rgb {
                own
            } else {
                CGColorSpace(name: CGColorSpace.displayP3)!
            }
        guard let result = context.createCGImage(out, from: target, format: .BGRA8, colorSpace: space) else {
            return nil
        }
        return FitImage(cgImage: result)
    }
}
