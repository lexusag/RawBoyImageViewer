import CoreGraphics
import Foundation
import ImageIO
import RawBoyBrowseKit
import UniformTypeIdentifiers

/// Draws a `CollageLayout` into one sRGB picture and writes it as a JPEG.
public enum CollageRenderer {
    /// The collage at its canvas size: the background colour, then each photo filling its frame (cropped at the
    /// edges) in drawing order. A photo missing from [images] leaves its frame as background.
    public static func render(_ layout: CollageLayout, images: [String: CGImage]) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: layout.canvas.width, height: layout.canvas.height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let height = Double(layout.canvas.height)
        context.setFillColor(
            red: CGFloat((layout.background >> 16) & 0xFF) / 255, green: CGFloat((layout.background >> 8) & 0xFF) / 255,
            blue: CGFloat(layout.background & 0xFF) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: layout.canvas.width, height: layout.canvas.height))
        context.interpolationQuality = .high
        for item in layout.items {
            guard let image = images[item.id] else { continue }
            let frame = layout.drawnFrame(item.frame)
            let cover = CollageLayout.coverRect(
                image: Size2D(width: Double(image.width), height: Double(image.height)), in: frame)
            // The layout is y down, CGContext's origin is bottom left.
            func flipped(_ r: Rect2D) -> CGRect { CGRect(x: r.x, y: height - r.maxY, width: r.width, height: r.height) }
            context.saveGState()
            context.clip(to: flipped(frame))
            context.draw(image, in: flipped(cover))
            context.restoreGState()
        }
        return context.makeImage()
    }

    /// Encodes [image] as a JPEG at [quality] (0...1).
    public static func jpegData(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard
            let dest = CGImageDestinationCreateWithData(
                data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Writes [image] as "[stem].jpg" in [folder] (created when missing; numbered when the name is taken).
    public static func writeJPEG(_ image: CGImage, quality: Double, to folder: URL, stem: String = "Collage") throws
        -> URL
    {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let out = Exporter.freeURL(in: folder, stem: stem, extension: "jpg")
        guard let data = jpegData(image, quality: quality) else {
            throw Exporter.ExportError.unwritable(out.lastPathComponent)
        }
        do {
            try data.write(to: out, options: .atomic)
        } catch {
            throw Exporter.ExportError.unwritable(out.lastPathComponent)
        }
        return out
    }
}
