import Foundation
import ImageIO
import RawBoyBrowseKit

/// What the details panel shows about a photo, read by ImageIO from the file's headers (raws included, without
/// decoding them).
public struct PhotoMetadata: Equatable, Sendable {
    public var camera: String?
    public var lens: String?
    public var taken: Date?
    public var shutter: String?
    public var aperture: String?
    public var iso: String?
    public var bias: String?
    public var focalLength: String?
    public var program: String?
    public var metering: String?
    public var flash: String?
    public var whiteBalance: String?
    public var colourProfile: String?
    public var bitDepth: Int?
    public var coordinates: String?
    /// For opening a map.
    public var latitude: Double?
    public var longitude: Double?
    public var altitude: String?
    public var software: String?
    public var artist: String?
    public var copyright: String?
    public var serialNumber: String?

    public init() {}

    /// "1/240 s · f/2.8 · ISO 100", from what is known.
    public var exposureSummary: String? {
        let parts = [shutter, aperture, iso].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    /// The metadata of [url], or nil when ImageIO can't read it.
    public static func read(_ url: URL) -> PhotoMetadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        return make(props)
    }

    static func make(_ props: [CFString: Any]) -> PhotoMetadata {
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let aux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        func number(_ dict: [CFString: Any], _ key: CFString) -> Double? { (dict[key] as? NSNumber)?.doubleValue }
        func text(_ dict: [CFString: Any], _ key: CFString) -> String? {
            (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
                .nonEmpty
        }

        var m = PhotoMetadata()
        m.camera = ExifFormat.camera(
            make: text(tiff, kCGImagePropertyTIFFMake), model: text(tiff, kCGImagePropertyTIFFModel))
        let lensModel = text(exif, kCGImagePropertyExifLensModel) ?? text(aux, kCGImagePropertyExifAuxLensModel)
        let lensMake = text(exif, kCGImagePropertyExifLensMake)
        if let lensModel {
            m.lens =
                lensMake.map { lensModel.lowercased().hasPrefix($0.lowercased()) ? lensModel : "\($0) \(lensModel)" }
                ?? lensModel
        }
        m.taken = ExifFormat.date(
            text(exif, kCGImagePropertyExifDateTimeOriginal) ?? text(tiff, kCGImagePropertyTIFFDateTime))
        m.shutter = number(exif, kCGImagePropertyExifExposureTime).flatMap(ExifFormat.shutter)
        m.aperture = number(exif, kCGImagePropertyExifFNumber).flatMap(ExifFormat.aperture)
        if let isos = exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber], let first = isos.first {
            m.iso = ExifFormat.iso(first.intValue)
        }
        m.bias = number(exif, kCGImagePropertyExifExposureBiasValue).map(ExifFormat.bias)
        m.focalLength = ExifFormat.focalLength(
            number(exif, kCGImagePropertyExifFocalLength),
            equivalent35: number(exif, kCGImagePropertyExifFocalLenIn35mmFilm))
        m.program = number(exif, kCGImagePropertyExifExposureProgram).flatMap { ExifFormat.program(Int($0)) }
        m.metering = number(exif, kCGImagePropertyExifMeteringMode).flatMap { ExifFormat.metering(Int($0)) }
        m.flash = number(exif, kCGImagePropertyExifFlash).map { ExifFormat.flash(Int($0)) }
        m.whiteBalance = number(exif, kCGImagePropertyExifWhiteBalance).flatMap { ExifFormat.whiteBalance(Int($0)) }
        m.colourProfile = props[kCGImagePropertyProfileName] as? String
        m.bitDepth = (props[kCGImagePropertyDepth] as? NSNumber)?.intValue
        if let lat = number(gps, kCGImagePropertyGPSLatitude), let lon = number(gps, kCGImagePropertyGPSLongitude) {
            let latRef = text(gps, kCGImagePropertyGPSLatitudeRef)
            let lonRef = text(gps, kCGImagePropertyGPSLongitudeRef)
            m.coordinates = ExifFormat.coordinates(
                latitude: lat, latitudeRef: latRef, longitude: lon, longitudeRef: lonRef)
            m.latitude = latRef == "S" ? -lat : lat
            m.longitude = lonRef == "W" ? -lon : lon
            if let alt = number(gps, kCGImagePropertyGPSAltitude) {
                let below = number(gps, kCGImagePropertyGPSAltitudeRef) == 1
                m.altitude = "\(Int(alt.rounded())) m\(below ? " below sea level" : "")"
            }
        }
        m.software = text(tiff, kCGImagePropertyTIFFSoftware)
        m.artist = text(tiff, kCGImagePropertyTIFFArtist)
        m.copyright = text(tiff, kCGImagePropertyTIFFCopyright)
        m.serialNumber =
            text(exif, kCGImagePropertyExifBodySerialNumber) ?? text(aux, kCGImagePropertyExifAuxSerialNumber)
        return m
    }
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
