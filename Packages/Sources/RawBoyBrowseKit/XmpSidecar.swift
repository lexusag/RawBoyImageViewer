import Foundation

/// Ratings in XMP sidecars, as Lightroom, Capture One and darktable read them: xmp:Rating 0-5 stars, -1 = rejected.
/// Picks have no standard XMP field, so RawBoy keeps them in its own namespace (rawboy:Pick="1").
///
/// Existing sidecars usually hold another app's edits: only RawBoy's fields are changed, in place, and everything
/// else is kept byte for byte. A port of RawBoy's `XmpSidecar.ts` (ratings part): keep the two in step.
public enum XmpSidecar {
    static let xmpNS = "http://ns.adobe.com/xap/1.0/"
    static let rawboyNS = "http://ns.rawboy.app/1.0/"

    public enum WriteError: Error, Equatable {
        /// The text has no rdf:Description to add the rating to.
        case notASidecar
    }

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
}
