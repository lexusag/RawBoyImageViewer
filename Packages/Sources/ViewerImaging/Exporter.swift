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

    /// The long edge in pixels; nil keeps the full size.
    public var longEdge: Int?
    public var format: Format
    /// 0...1.
    public var quality: Double
    /// Leave the GPS position out.
    public var removeLocation: Bool

    public init(longEdge: Int? = 3000, format: Format = .jpeg, quality: Double = 0.9, removeLocation: Bool = false) {
        self.longEdge = longEdge
        self.format = format
        self.quality = quality
        self.removeLocation = removeLocation
    }

    /// The sizes the export sheet offers.
    public static let sizes: [Int?] = [nil, 3000, 2048, 1080]
}

/// Writes a photo as a new JPEG or HEIC: resized, turned as its sidecar says, its colour profile and EXIF kept (the
/// location only when asked), never overwriting a file. Raws are developed by macOS as shot (not RawBoy's look).
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

    /// Exports [url] into [folder]; returns the new file.
    public static func export(
        _ url: URL, orientation: Int?, crop: CropRect? = nil, to folder: URL, options: ExportOptions
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
        let turned = Orientation(exif: fileOrientation).then(
            Orienting.delta(from: fileOrientation, to: orientation ?? fileOrientation))
        let (w, h) = turned.isQuarterTurned ? (Double(height), Double(width)) : (Double(width), Double(height))
        let c = crop ?? .full
        let croppedLong = max(w * c.width, h * c.height)
        let scale = min(1, Double(options.longEdge ?? longEdge) / croppedLong)
        let target = max(1, Int((Double(longEdge) * scale).rounded()))
        guard
            var image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: target,
                ] as CFDictionary)
        else { throw ExportError.unreadable(name) }
        if let orientation {
            image = Orienting.apply(Orienting.delta(from: fileOrientation, to: orientation), to: image)
        }
        image = Orienting.crop(image, crop)

        let out = freeURL(in: folder, stem: PhotoGroups.stem(of: name), extension: options.format.fileExtension)
        guard
            let dest = CGImageDestinationCreateWithURL(out as CFURL, options.format.type.identifier as CFString, 1, nil)
        else { throw ExportError.unwritable(out.lastPathComponent) }
        CGImageDestinationAddImage(dest, image, metadata(props, options) as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.unwritable(out.lastPathComponent) }
        return out
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
