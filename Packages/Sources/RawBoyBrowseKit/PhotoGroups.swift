import Foundation

/// One photo of a folder: its files sharing a base name (a RAW + JPEG pair is one photo) and their sidecars.
/// A port of RawBoy Browser's `PhotoGroups.ts`: keep the two in step.
public struct PhotoGroup: Equatable, Sendable {
    /// The base name of [main].
    public let stem: String
    /// The file shown and opened: the raw when there is one.
    public let main: String
    /// The other files of the photo (the JPEG of a RAW + JPEG pair); they go to the bin with it.
    public let companions: [String]
    /// Existing XMP sidecars: NAME.xmp (Lightroom, Capture One), NAME.EXT.xmp (darktable) and darktable's duplicates'
    /// NAME_01.EXT.xmp.
    public let sidecars: [String]

    public init(stem: String, main: String, companions: [String], sidecars: [String]) {
        self.stem = stem
        self.main = main
        self.companions = companions
        self.sidecars = sidecars
    }
}

public enum PhotoGroups {
    /// [name] without its last extension ("IMG_1.CR2.xmp" → "IMG_1.CR2"). A leading dot is not an extension.
    public static func stem(of name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }

    static func isRaw(_ name: String) -> Bool { PhotoFileType(fileName: name) == .raw }
    static func isPhoto(_ name: String) -> Bool { PhotoFileType(fileName: name) != nil }
    static func isSidecar(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        return name[name.index(after: dot)...].lowercased() == "xmp"
    }

    /// Groups a folder's file names into photos, in natural name order; other files are ignored. Names compare
    /// case-insensitively.
    public static func group(_ names: [String]) -> [PhotoGroup] {
        let photos = names.filter(isPhoto)
        let photoNames = Set(photos.map { $0.lowercased() })
        var byStem: [String: [String]] = [:]
        for name in photos {
            byStem[stem(of: name).lowercased(), default: []].append(name)
        }

        var sidecars: [String: [String]] = [:]
        for name in names where isSidecar(name) {
            // NAME.xmp belongs to NAME; NAME.CR2.xmp to NAME.CR2's stem.
            let inner = stem(of: name)
            var key = (isPhoto(inner) ? stem(of: inner) : inner).lowercased()
            // darktable's duplicates of NAME.CR2 are NAME_01.CR2.xmp, NAME_02.CR2.xmp…, with no file of their own.
            if let (base, ext) = duplicateParts(inner), !photoNames.contains(inner.lowercased()),
                photoNames.contains((base + ext).lowercased())
            {
                key = stem(of: base + ext).lowercased()
            }
            sidecars[key, default: []].append(name)
        }

        let groups = byStem.map { key, files -> PhotoGroup in
            let sorted = files.sorted { a, b in
                isRaw(a) != isRaw(b) ? isRaw(a) : a.localizedStandardCompare(b) == .orderedAscending
            }
            return PhotoGroup(
                stem: stem(of: sorted[0]), main: sorted[0], companions: Array(sorted.dropFirst()),
                sidecars: (sidecars[key] ?? []).sorted())
        }
        return groups.sorted { $0.main.localizedStandardCompare($1.main) == .orderedAscending }
    }

    /// darktable's duplicate naming: the photo's stem, "_" and the version number, then its extension.
    /// "IMG_1_01.CR2" → ("IMG_1", ".CR2").
    static func duplicateParts(_ name: String) -> (String, String)? {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return nil }
        let ext = String(name[dot...])
        guard ext.count > 1, !ext.dropFirst().contains(".") else { return nil }
        let head = name[..<dot]
        guard let underscore = head.lastIndex(of: "_") else { return nil }
        let digits = head[head.index(after: underscore)...]
        guard !digits.isEmpty, digits.allSatisfy(\.isASCIIDigit) else { return nil }
        return (String(head[..<underscore]), ext)
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isNumber }
}
