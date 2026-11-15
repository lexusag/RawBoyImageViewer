import CoreGraphics
import Foundation
import ImageIO
import RawBoyBrowseKit
import UniformTypeIdentifiers

/// How photos are exported.
public struct ExportOptions: Codable, Equatable, Sendable {
    public enum Format: String, Codable, CaseIterable, Sendable {
        case jpeg, heic

        public var fileExtension: String { self == .jpeg ? "jpg" : "heic" }
        var type: UTType { self == .jpeg ? .jpeg : .heic }
    }

    /// A fixed aspect ratio (width : height) applied on export, centred on the photo (or on its crop).
    public enum Crop: String, Codable, CaseIterable, Sendable {
        case threeFour = "3:4"
        case fourFive = "4:5"
        case square = "1:1"
        case landscape = "1.91:1"
        case nineSixteen = "9:16"

        /// Width / height in pixels.
        public var ratio: Double {
            switch self {
            case .threeFour: 3.0 / 4.0
            case .fourFive: 4.0 / 5.0
            case .square: 1
            case .landscape: 1.91
            case .nineSixteen: 9.0 / 16.0
            }
        }
    }

    /// The long edge in pixels; nil keeps the full size.
    public var longEdge: Int?
    /// The short edge in pixels (1440 for Instagram); nil leaves it free. With a long edge too, the smaller result
    /// wins. Photos are never enlarged.
    public var shortEdge: Int?
    /// An aspect ratio to crop to on export (centred on the photo or its existing crop); nil keeps the photo's own.
    public var crop: Crop?
    /// Convert the pixels to sRGB (what Instagram shows) instead of keeping the photo's own colour profile.
    public var convertToSRGB: Bool
    public var format: Format
    /// 0...1.
    public var quality: Double
    /// Leave the GPS position out.
    public var removeLocation: Bool
    /// Replace a file of the same name in the destination (the old one goes to the Trash) instead of numbering the
    /// new one. Never applies to the photo's own folder, which holds the originals.
    public var replaceExisting: Bool

    public init(
        longEdge: Int? = 3000, shortEdge: Int? = nil, crop: Crop? = nil, convertToSRGB: Bool = false,
        format: Format = .jpeg, quality: Double = 0.9, removeLocation: Bool = false, replaceExisting: Bool = false
    ) {
        self.longEdge = longEdge
        self.shortEdge = shortEdge
        self.crop = crop
        self.convertToSRGB = convertToSRGB
        self.format = format
        self.quality = quality
        self.removeLocation = removeLocation
        self.replaceExisting = replaceExisting
    }

    // Saved options and presets from before `replaceExisting` or `crop` have no such keys.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        longEdge = try c.decodeIfPresent(Int.self, forKey: .longEdge)
        shortEdge = try c.decodeIfPresent(Int.self, forKey: .shortEdge)
        crop = try c.decodeIfPresent(Crop.self, forKey: .crop)
        convertToSRGB = try c.decodeIfPresent(Bool.self, forKey: .convertToSRGB) ?? false
        format = try c.decode(Format.self, forKey: .format)
        quality = try c.decode(Double.self, forKey: .quality)
        removeLocation = try c.decode(Bool.self, forKey: .removeLocation)
        replaceExisting = try c.decodeIfPresent(Bool.self, forKey: .replaceExisting) ?? false
    }

    /// The sizes the export sheet offers.
    public static let sizes: [Int?] = [nil, 3000, 2048, 1080]

    /// Instagram's feed size: 1440 px on the short edge, sRGB JPEG, no long-edge limit.
    public static let instagramShortEdge = 1440

    /// The one-click Instagram settings, keeping the quality, location and replace choices of [base] (and its
    /// Instagram crop when one is already chosen, else 3:4).
    public static func instagram(from base: ExportOptions = ExportOptions()) -> ExportOptions {
        var o = base
        o.longEdge = nil
        o.shortEdge = instagramShortEdge
        o.crop = base.crop ?? .threeFour
        o.convertToSRGB = true
        o.format = .jpeg
        return o
    }

    public var isInstagram: Bool {
        longEdge == nil && shortEdge == Self.instagramShortEdge && crop != nil && convertToSRGB && format == .jpeg
    }
}

/// Writes a photo as a new JPEG or HEIC: resized, turned as its sidecar says, its colour profile and EXIF kept (the
/// location only when asked), never overwriting a file unless asked (the old one goes to the Trash). Raws are developed by macOS as shot (not RawBoy's look).
public enum Exporter {
    public enum ExportError: LocalizedError {
        case unreadable(String), unwritable(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let name): "Can't read \(name)."
            case .unwritable(let name): "Can't write \(name)."
            }
        }
    }

    /// [crop] (or the whole frame) fitted to [aspect] (width / height in pixels) around its centre, inside the frame.
    public static func effectiveCrop(_ crop: CropRect?, aspect: ExportOptions.Crop?, width: Double, height: Double)
        -> CropRect
    {
        let r = crop ?? .full
        guard let ratio = aspect?.ratio, width > 0, height > 0 else { return r }
        let cw = r.width * width
        let ch = r.height * height
        let w = min(cw, ch * ratio)
        let h = w / ratio
        let cx = (r.left + r.right) / 2 * width
        let cy = (r.top + r.bottom) / 2 * height
        return CropRect(
            left: (cx - w / 2) / width, top: (cy - h / 2) / height,
            right: (cx + w / 2) / width, bottom: (cy + h / 2) / height)
    }

    /// Exports [url] into [folder]; returns the new file. The name is [stem] (the photo's own by default) plus
    /// [suffix].
    public static func export(
        _ url: URL, orientation: Int?, crop: CropRect? = nil, to folder: URL, options: ExportOptions,
        stem: String? = nil, suffix: String = ""
    ) throws -> URL {
        let name = url.lastPathComponent
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int
        else { throw ExportError.unreadable(name) }
        let longEdge = max(width, height)
        // The long edge asked for is the cropped photo's: decode enough of the whole one for it. The crop is in the
        // turned photo, so its size is measured there.
        let fileOrientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        let delta = Orienting.delta(from: fileOrientation, to: orientation ?? fileOrientation)
        let turned = Orientation(exif: fileOrientation).then(delta)
        let (w, h) = turned.isQuarterTurned ? (Double(height), Double(width)) : (Double(width), Double(height))
        let c = effectiveCrop(crop, aspect: options.crop, width: w, height: h)
        let croppedLong = max(w * c.width, h * c.height)
        let croppedShort = min(w * c.width, h * c.height)
        let scale = min(
            1, Double(options.longEdge ?? longEdge) / croppedLong,
            options.shortEdge.map { Double($0) / croppedShort } ?? 1)
        var image: CGImage
        if let ratio = options.crop?.ratio {
            // A fixed ratio must come out as exact integers (Instagram resizes anything else): decode a little more
            // than needed, then draw the crop into a context of exactly the wanted size.
            let short = max(1, Int((croppedShort * scale).rounded()))
            let (outW, outH) = exactSize(short: short, ratio: ratio)
            let needed = Double(outW) / max(1e-9, w * c.width)
            let target = min(longEdge, Int((Double(longEdge) * needed).rounded(.up)) + 2)
            guard let t = thumbnail(source, maxPixel: max(1, target)) else { throw ExportError.unreadable(name) }
            let turnedImage = Orienting.apply(delta, to: t)
            guard
                let drawn = drawCrop(
                    turnedImage, c, width: outW, height: outH, srgb: options.convertToSRGB)
            else { throw ExportError.unreadable(name) }
            image = drawn
        } else {
            var target = max(1, Int((Double(longEdge) * scale).rounded()))
            // ImageIO sizes by the long edge and rounds the short one down (1439 for a 1440 request): nudge the long
            // edge up until the cropped short edge is the rounded size asked for.
            let wantedShort = Int((croppedShort * scale).rounded())
            let maxLong = options.longEdge ?? Int.max
            var decoded: CGImage?
            for _ in 0..<4 {
                decoded = thumbnail(source, maxPixel: target)
                guard let t = decoded else { break }
                let (tw, th) =
                    delta.isQuarterTurned ? (Double(t.height), Double(t.width)) : (Double(t.width), Double(t.height))
                let cw = Int((c.width * tw).rounded())
                let ch = Int((c.height * th).rounded())
                if scale >= 1 || min(cw, ch) >= wantedShort || max(cw, ch) >= maxLong { break }
                target += 1
            }
            guard let d = decoded else { throw ExportError.unreadable(name) }
            image = Orienting.crop(Orienting.apply(delta, to: d), c)
        }
        if options.convertToSRGB { image = toSRGB(image) }

        let fullStem = (stem ?? PhotoGroups.stem(of: name)) + suffix
        let ext = options.format.fileExtension
        // Replacing is for other folders only: the photo's own folder holds the originals (and a RAW's JPEG).
        let replacing =
            options.replaceExisting
            && folder.standardizedFileURL.resolvingSymlinksInPath()
                != url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        let out =
            replacing
            ? folder.appendingPathComponent("\(fullStem).\(ext)") : freeURL(in: folder, stem: fullStem, extension: ext)
        // Written beside the target first, so a failed export never costs the file already there.
        let written =
            replacing
            ? folder.appendingPathComponent(".\(fullStem)-\(UUID().uuidString.prefix(8)).\(ext)") : out
        guard
            let dest = CGImageDestinationCreateWithURL(
                written as CFURL, options.format.type.identifier as CFString, 1, nil)
        else { throw ExportError.unwritable(out.lastPathComponent) }
        CGImageDestinationAddImage(dest, image, metadata(props, options) as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            if replacing { try? FileManager.default.removeItem(at: written) }
            throw ExportError.unwritable(out.lastPathComponent)
        }
        if replacing {
            do { try swap(written, into: out) } catch {
                try? FileManager.default.removeItem(at: written)
                throw ExportError.unwritable(out.lastPathComponent)
            }
        }
        return out
    }

    /// Width and height for [short] (the short edge) at [ratio] (width / height), the long edge rounded to an integer.
    public static func exactSize(short: Int, ratio: Double) -> (Int, Int) {
        ratio < 1
            ? (short, max(1, Int((Double(short) / ratio).rounded())))
            : (max(1, Int((Double(short) * ratio).rounded())), short)
    }

    static func thumbnail(_ source: CGImageSource, maxPixel: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(
            source, 0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            ] as CFDictionary)
    }

    /// The part [crop] (fractions, y down) of [image] resampled into exactly [width] x [height] pixels.
    static func drawCrop(_ image: CGImage, _ crop: CropRect, width: Int, height: Int, srgb: Bool) -> CGImage? {
        let sRGBSpace = CGColorSpace(name: CGColorSpace.sRGB)
        var space = srgb ? sRGBSpace : (image.colorSpace ?? sRGBSpace)
        if space?.model != .rgb { space = sRGBSpace }
        guard let space else { return nil }
        let info = CGImageAlphaInfo.noneSkipLast.rawValue
        guard
            let context =
                CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: info)
                ?? CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: sRGBSpace ?? space, bitmapInfo: info)
        else { return nil }
        context.interpolationQuality = .high
        let iw = Double(image.width)
        let ih = Double(image.height)
        let sx = Double(width) / max(1e-9, crop.width * iw)
        let sy = Double(height) / max(1e-9, crop.height * ih)
        // CGContext's origin is bottom left, the crop's top is measured from the top.
        context.draw(
            image,
            in: CGRect(
                x: -crop.left * iw * sx, y: -(1 - crop.bottom) * ih * sy, width: iw * sx, height: ih * sy))
        return context.makeImage()
    }

    /// [image] redrawn in sRGB (the original when it already is, or when the conversion fails).
    static func toSRGB(_ image: CGImage) -> CGImage {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB), image.colorSpace?.name != srgb.name,
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }

    /// Puts [new] at [target]. An old file there goes to the Trash (permanently replaced where there is none, e.g.
    /// on a network volume).
    static func swap(_ new: URL, into target: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: target.path) {
            do { try fm.trashItem(at: target, resultingItemURL: nil) } catch {
                _ = try fm.replaceItemAt(target, withItemAt: new)
                return
            }
        }
        try fm.moveItem(at: new, to: target)
    }

    /// The source's EXIF, TIFF, IPTC and (unless removed) GPS, with the pixels now upright and the quality set.
    static func metadata(_ props: [CFString: Any], _ options: ExportOptions) -> [CFString: Any] {
        var out: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: options.quality]
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyExifAuxDictionary] {
            if let dict = props[key] { out[key] = dict }
        }
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            out[kCGImagePropertyTIFFDictionary] = tiff
        }
        if !options.removeLocation, let gps = props[kCGImagePropertyGPSDictionary] {
            out[kCGImagePropertyGPSDictionary] = gps
        }
        out[kCGImagePropertyOrientation] = 1
        return out
    }

    /// [folder]/[stem].[extension], or with "-1", "-2"... when taken.
    public static func freeURL(in folder: URL, stem: String, extension ext: String) -> URL {
        var url = folder.appendingPathComponent("\(stem).\(ext)")
        var k = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(stem)-\(k).\(ext)")
            k += 1
        }
        return url
    }
}
