import Foundation

/// Ratings, orientation and RawBoy's edits in XMP sidecars, as Lightroom, Capture One and darktable read them:
/// xmp:Rating 0-5 stars, -1 = rejected. Picks have no standard XMP field, so RawBoy keeps them in its own namespace
/// (rawboy:Pick="1"), with its edits (rawboy:Develop) and Auto settings (rawboy:Auto).
///
/// Existing sidecars usually hold another app's edits: only RawBoy's fields are changed, in place, and everything
/// else is kept byte for byte. A port of RawBoy's `XmpSidecar.ts`: keep the two in step. This is the one Swift copy
/// (RawBoy's iOS/Desktop engine names, `readRating`, `writeRating`, `ExifOrientation` and `PhotoSidecar`, are here too).
public enum XmpSidecar {
    static let xmpNS = "http://ns.adobe.com/xap/1.0/"
    static let rawboyNS = "http://ns.rawboy.app/1.0/"

    public enum WriteError: Error, Equatable {
        /// The text has no rdf:Description to add the rating to.
        case notASidecar
    }

    /// The engine's names for the rating types, which it nests here.
    public typealias Rating = RawBoyBrowseKit.Rating
    public typealias Flag = RawBoyBrowseKit.Flag

    /// The rating in a sidecar's text (the engine's `readRating`).
    public static func readRating(_ text: String) -> Rating { read(text) }

    /// [text] (nil: a new sidecar) with [rating] written into it (the engine's `writeRating`).
    public static func writeRating(_ text: String?, _ rating: Rating) throws -> String { try write(text, rating) }

    /// The rating in a sidecar's text.
    public static func read(_ text: String) -> Rating {
        let rating = fieldValue(text, "xmp:Rating").flatMap(Double.init) ?? 0
        let pick = fieldValue(text, "rawboy:Pick") == "1"
        if rating < 0 { return Rating(stars: 0, flag: .reject) }
        return Rating(stars: max(0, min(5, Int(rating.rounded()))), flag: pick ? .pick : nil)
    }

    /// Whether [text] holds a rating or a pick (RawBoy reads the first sidecar that does).
    public static func hasRating(_ text: String) -> Bool {
        text.contains("xmp:Rating") || text.contains("rawboy:Pick")
    }

    /// [text] (nil: a new sidecar) with [rating] written into it.
    public static func write(_ text: String?, _ rating: Rating) throws -> String {
        var out = text ?? empty
        out = try setField(out, "xmp:Rating", "xmp", xmpNS, String(rating.flag == .reject ? -1 : rating.stars))
        out = try setField(out, "rawboy:Pick", "rawboy", rawboyNS, rating.flag == .pick ? "1" : nil)
        return out
    }

    static let tiffNS = "http://ns.adobe.com/tiff/1.0/"

    /// The orientation a sidecar sets for its photo (`tiff:Orientation`, where Lightroom keeps a rotation of a raw),
    /// or nil.
    public static func readOrientation(_ text: String) -> Int? {
        fieldValue(text, "tiff:Orientation").flatMap { Int($0) }.flatMap { (1...8).contains($0) ? $0 : nil }
    }

    /// [text] (nil: a new sidecar) with `tiff:Orientation` set to [orientation]; nil removes it.
    public static func writeOrientation(_ text: String?, _ orientation: Int?) throws -> String {
        try setField(text ?? empty, "tiff:Orientation", "tiff", tiffNS, orientation.map(String.init))
    }

    /// A photo's RawBoy Auto settings (`rawboy:Auto`, escaped `AutoSidecar` JSON) in a sidecar's text, or nil.
    public static func readAuto(_ text: String) -> String? {
        fieldValue(text, "rawboy:Auto").flatMap { $0.isEmpty ? nil : unescapeXml($0) }
    }

    /// [text] with RawBoy's Auto settings set to [json] (nil removes them); the other fields stay as they are.
    public static func writeAuto(_ text: String?, _ json: String?) throws -> String {
        try setField(text ?? empty, "rawboy:Auto", "rawboy", rawboyNS, json.map(escapeXml))
    }

    /// RawBoy's edits (`rawboy:Develop`, escaped `Edits` JSON) in a sidecar's text, or nil.
    public static func readDevelop(_ text: String) -> String? {
        fieldValue(text, "rawboy:Develop").flatMap { $0.isEmpty ? nil : unescapeXml($0) }
    }

    /// [text] (nil: a new sidecar) with RawBoy's edits set to [json]; nil removes them.
    public static func writeDevelop(_ text: String?, _ json: String?) throws -> String {
        try setField(text ?? empty, "rawboy:Develop", "rawboy", rawboyNS, json.map(escapeXml))
    }

    static let empty = """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="RawBoy">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""/>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>

        """

    /// An attribute (name="v") or simple element (<name>v</name>) form of [name].
    static func attributeRe(_ name: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"(\s"# + escape(name) + #"\s*=\s*)(["'])((?:(?!\2)[^<])*)\2"#)
    }

    static func elementRe(_ name: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "(<" + escape(name) + ">)([^<]*)(</" + escape(name) + ">)")
    }

    static func escape(_ s: String) -> String { NSRegularExpression.escapedPattern(for: s) }

    static func fieldValue(_ text: String, _ name: String) -> String? {
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        if let m = attributeRe(name).firstMatch(in: text, range: all) {
            return ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let m = elementRe(name).firstMatch(in: text, range: all) {
            return ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// Sets [name] to [value] where it already is (attribute or element), else adds it as an attribute of the first
    /// rdf:Description, declaring [prefix] there if that element doesn't. A nil value removes the field.
    static func setField(_ text: String, _ name: String, _ prefix: String, _ ns: String, _ value: String?) throws
        -> String
    {
        let nsText = text as NSString
        let all = NSRange(location: 0, length: nsText.length)
        if let m = attributeRe(name).firstMatch(in: text, range: all) {
            guard let value else { return nsText.replacingCharacters(in: m.range, with: "") }
            return nsText.replacingCharacters(in: m.range(at: 3), with: value)
        }
        if let m = elementRe(name).firstMatch(in: text, range: all) {
            if let value { return nsText.replacingCharacters(in: m.range(at: 2), with: value) }
            // swiftlint:disable:next force_try
            let whole = try! NSRegularExpression(pattern: #"\s*<"# + escape(name) + ">[^<]*</" + escape(name) + ">")
            guard let w = whole.firstMatch(in: text, range: all) else { return text }
            return nsText.replacingCharacters(in: w.range, with: "")
        }
        guard let value else { return text }
        // swiftlint:disable:next force_try
        let descriptionRe = try! NSRegularExpression(pattern: #"<rdf:Description\b[^>]*?(?=\/?>)"#)
        guard let d = descriptionRe.firstMatch(in: text, range: all) else { throw WriteError.notASidecar }
        let description = nsText.substring(with: d.range)
        let declared = description.range(of: #"\sxmlns:"# + escape(prefix) + #"\s*="#, options: .regularExpression)
        let added = (declared != nil ? "" : "\n   xmlns:\(prefix)=\"\(ns)\"") + "\n   \(name)=\"\(value)\""
        return nsText.replacingCharacters(in: NSRange(location: d.range.upperBound, length: 0), with: added)
    }

    static func escapeXml(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    static func unescapeXml(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var rest = Substring(s)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            guard let semi = rest[amp...].firstIndex(of: ";") else { break }
            let entity = rest[rest.index(after: amp)..<semi]
            switch entity.lowercased() {
            case "amp": out += "&"
            case "lt": out += "<"
            case "gt": out += ">"
            case "quot": out += "\""
            case "apos": out += "'"
            default:
                let code: UInt32? =
                    entity.hasPrefix("#x") || entity.hasPrefix("#X")
                    ? UInt32(entity.dropFirst(2), radix: 16) : entity.hasPrefix("#") ? UInt32(entity.dropFirst()) : nil
                if let code, let scalar = Unicode.Scalar(code) {
                    out.unicodeScalars.append(scalar)
                } else {
                    out += rest[amp...semi]
                }
            }
            rest = rest[rest.index(after: semi)...]
        }
        return out + rest
    }
}

/// The engine's name for [Orientation].
public typealias ExifOrientation = Orientation

extension Orientation {
    /// What a sidecar's `tiff:Orientation` ([sidecar]) adds on top of the photo's own orientation ([file]).
    public static func delta(file: Int, sidecar: Int) -> Orientation {
        Orientation(exif: file).inverse.then(Orientation(exif: sidecar))
    }
}

/// Where a photo's sidecar is and how RawBoy Desktop reads and writes it (web's `BrowserStore.editsSidecar`): NAME.xmp
/// next to the photo, else darktable's NAME.EXT.xmp, else a new NAME.xmp. Every write reads the file afresh and changes
/// only RawBoy's field, atomically, so it never undoes another app's (or the Viewer's) write.
public struct PhotoSidecar: Sendable {
    public let photo: URL

    public init(photo: URL) { self.photo = photo }

    /// The sidecar's URL: an existing NAME.xmp or NAME.EXT.xmp (matched ignoring case), else the NAME.xmp to create.
    public var url: URL {
        let dir = photo.deletingLastPathComponent()
        let stem = photo.deletingPathExtension().lastPathComponent
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        func named(_ n: String) -> String? { names.first { $0.caseInsensitiveCompare(n) == .orderedSame } }
        let name = named(stem + ".xmp") ?? named(photo.lastPathComponent + ".xmp") ?? stem + ".xmp"
        return dir.appendingPathComponent(name)
    }

    /// The sidecar's text, or nil when there is none.
    public func readText() -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    /// RawBoy's edits JSON in the sidecar (`rawboy:Develop`), or nil.
    public func readDevelop() -> String? { readText().flatMap(XmpSidecar.readDevelop) }

    /// RawBoy Auto's settings JSON in the sidecar (`rawboy:Auto`), or nil.
    public func readAuto() -> String? { readText().flatMap(XmpSidecar.readAuto) }

    /// The sidecar's `tiff:Orientation`, or nil.
    public func readOrientation() -> Int? { readText().flatMap(XmpSidecar.readOrientation) }

    /// Sets RawBoy's edits ([json], nil removes them); a missing sidecar is created only for non-nil edits. Skipped when
    /// nothing changes. Atomic (a temporary file moved over the sidecar).
    public func writeDevelop(_ json: String?) throws { try update(json, XmpSidecar.writeDevelop) }

    /// As `writeDevelop`, for RawBoy Auto's settings (`rawboy:Auto`).
    public func writeAuto(_ json: String?) throws { try update(json, XmpSidecar.writeAuto) }

    private func update(_ json: String?, _ write: (String?, String?) throws -> String) throws {
        let url = self.url
        let old = try? String(contentsOf: url, encoding: .utf8)
        if old == nil && json == nil { return }
        let out = try write(old, json)
        if out == old { return }
        try Data(out.utf8).write(to: url, options: .atomic)
    }
}
