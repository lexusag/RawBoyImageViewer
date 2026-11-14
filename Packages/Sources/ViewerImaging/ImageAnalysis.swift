import CoreGraphics
import Foundation
import RawBoyBrowseKit

/// The histogram and the clipping overlay of the picture on screen. Call off the main thread.
public enum ImageAnalysis {
    /// RawBoy measures a 512 px copy too: enough for the shape, quick to count.
    public static let histogramSize = 512
    /// The overlay is made at most this big; past it, pixels are enlarged (only visible far past 1:1).
    public static let overlaySize = 4096

    /// [image]'s histogram, counted on a copy at most [histogramSize] px long (nearest-neighbour, so a clipped pixel
    /// stays clipped).
    public static func histogram(of image: CGImage) -> Histogram? {
        guard let (context, _, _) = bgraCopy(of: image, maxPixelSize: histogramSize), let data = context.data else {
            return nil
        }
        let bytes = UnsafeRawBufferPointer(start: data, count: context.bytesPerRow * context.height)
        return Histogram(
            pixels: bytes, width: context.width, height: context.height, bytesPerRow: context.bytesPerRow,
            redOffset: 2, greenOffset: 1, blueOffset: 0)
    }

    /// RawBoy's clipping warning for [image]: red over clipped highlights, blue over crushed shadows, transparent
    /// elsewhere. Nil when nothing clips.
    public static func clipOverlay(of image: CGImage) -> CGImage? {
        guard let (source, width, height) = bgraCopy(of: image, maxPixelSize: overlaySize), let src = source.data,
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let out = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: source.bytesPerRow,
                space: space, bitmapInfo: ImageLoader.displayBitmapInfo.rawValue),
            let dst = out.data
        else { return nil }
        let count = source.bytesPerRow * height
        let any = ClipWarning.overlay(
            pixels: UnsafeRawBufferPointer(start: src, count: count),
            into: UnsafeMutableRawBufferPointer(start: dst, count: count), width: width, height: height,
            bytesPerRow: source.bytesPerRow, redOffset: 2, greenOffset: 1, blueOffset: 0)
        return any ? out.makeImage() : nil
    }

    /// [image] drawn into an 8-bit BGRA context in its own colour space, at most [maxPixelSize] long.
    private static func bgraCopy(of image: CGImage, maxPixelSize: Int) -> (CGContext, Int, Int)? {
        let scale = min(1, Double(maxPixelSize) / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: ImageLoader.displayBitmapInfo.rawValue)
        else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (context, width, height)
    }
}
