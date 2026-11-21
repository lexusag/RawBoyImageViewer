import Foundation
import ImageIO

/// One line of the full metadata list: a readable name and the value as text.
public struct MetadataEntry: Equatable, Sendable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// A block of metadata that belongs together (EXIF, GPS, a maker's notes, XMP...).
public struct MetadataGroup: Equatable, Sendable, Identifiable {
    public var name: String
    public var entries: [MetadataEntry]
    public var id: String { name }

    public init(name: String, entries: [MetadataEntry]) {
        self.name = name
        self.entries = entries
    }
}

/// Everything ImageIO finds in a file's headers: the standard EXIF, TIFF, GPS and IPTC blocks, the makers' notes it
/// can decode, the DNG tags, and every XMP property (so custom ones, such as RawBoy Camera's ImageDescription note
/// or `rawboy:` fields, show up). Read from the headers only, raws included; nothing is decoded.
public enum FullMetadata {
    /// The groups of [url], in reading order, or empty when ImageIO can't read it.
    public static func read(_ url: URL) -> [MetadataGroup] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return [] }
        var xmp: [MetadataEntry] = []
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { path, tag in
                if let value = CGImageMetadataTagCopyValue(tag), let text = format(value) {
                    xmp.append(MetadataEntry(name: path as String, value: text))
                }
                return true
            }
        }
        return groups(props, xmp: xmp)
    }

    /// Groups from ImageIO's property dictionary (the file's own scalars first, then each nested block) plus
    /// already flattened XMP entries.
    static func groups(_ props: [CFString: Any], xmp: [MetadataEntry]) -> [MetadataGroup] {
        var image: [MetadataEntry] = []
        var blocks: [(String, [MetadataEntry])] = []
        for (key, value) in props {
            let name = key as String
            if let dict = value as? [String: Any] {
                let entries = flatten(dict, prefix: "")
                if !entries.isEmpty { blocks.append((name, entries)) }
            } else if let text = format(value) {
                image.append(MetadataEntry(name: humanise(name), value: text))
            }
        }
        var out: [MetadataGroup] = []
        if !image.isEmpty { out.append(MetadataGroup(name: "Image", entries: sorted(image))) }
        for (name, entries) in blocks.sorted(by: { order($0.0, $1.0) }) {
            out.append(MetadataGroup(name: groupTitle(name), entries: sorted(entries)))
        }
        let xmpEntries = xmp.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if !xmpEntries.isEmpty { out.append(MetadataGroup(name: "XMP", entries: xmpEntries)) }
        return out
    }

    private static let blockOrder = ["{TIFF}", "{Exif}", "{ExifAux}", "{GPS}", "{IPTC}", "{DNG}", "{Raw}", "{JFIF}"]

    private static func order(_ a: String, _ b: String) -> Bool {
        let ia = blockOrder.firstIndex(of: a) ?? (a.hasPrefix("{Maker") ? blockOrder.count : blockOrder.count + 1)
        let ib = blockOrder.firstIndex(of: b) ?? (b.hasPrefix("{Maker") ? blockOrder.count : blockOrder.count + 1)
        return ia == ib ? a < b : ia < ib
    }

    private static func sorted(_ entries: [MetadataEntry]) -> [MetadataEntry] {
        entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// "{ExifAux}" → "EXIF extra", "{MakerFuji}" → "Maker note: Fuji".
    static func groupTitle(_ key: String) -> String {
        let name = key.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        switch name {
        case "TIFF": return "TIFF"
        case "Exif": return "EXIF"
        case "ExifAux": return "EXIF extra"
        case "GPS": return "GPS"
        case "IPTC": return "IPTC"
        case "DNG": return "DNG"
        case "Raw": return "Raw"
        case "JFIF": return "JFIF"
        default:
            if name.hasPrefix("Maker"), name.count > 5 { return "Maker note: " + humanise(String(name.dropFirst(5))) }
            return humanise(name)
        }
    }

    /// Nested blocks become "Parent Child" names.
    private static func flatten(_ dict: [String: Any], prefix: String) -> [MetadataEntry] {
        var out: [MetadataEntry] = []
        for (key, value) in dict {
            let name = prefix.isEmpty ? humanise(key) : prefix + " " + humanise(key)
            if let nested = value as? [String: Any] {
                out += flatten(nested, prefix: name)
            } else if let text = format(value) {
                out.append(MetadataEntry(name: name, value: text))
            }
        }
        return out
    }

    /// "ExposureTime" → "Exposure Time", "ISOSpeedRatings" → "ISO Speed Ratings", "FNumber" → "F Number",
    /// "1234" → "Tag 1234". Names with a space or colon (XMP paths) are left as they are.
    static func humanise(_ key: String) -> String {
        if key.isEmpty { return key }
        if key.allSatisfy(\.isNumber) { return "Tag " + key }
        if key.contains(" ") || key.contains(":") || key.contains("/") { return key }
        let chars = Array(key)
        var out = ""
        for (i, c) in chars.enumerated() {
            if i > 0, c.isUppercase {
                let before = chars[i - 1]
                let after = i + 1 < chars.count ? chars[i + 1] : nil
                // A word starts after a lowercase letter or digit, or where an acronym ends ("ISOSpeed" → "ISO Speed").
                if before.isLowercase || before.isNumber || (before.isUppercase && after?.isLowercase == true) {
                    out.append(" ")
                }
            }
            out.append(c)
        }
        return out
    }

    /// The most values of a list shown on one line.
    static let listLimit = 48

    /// A value as text: strings trimmed, numbers without trailing zeros, lists joined, binary as its size.
    /// Nil for what has no readable form.
    static func format(_ value: Any) -> String? {
        switch value {
        case let text as String:
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
            return t.isEmpty ? nil : t
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "Yes" : "No" }
            return numberText(n.doubleValue, integer: !CFNumberIsFloatType(n))
        case let data as Data:
            return "\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)) of binary data"
        case let date as Date:
            return date.formatted(date: .abbreviated, time: .standard)
        case let list as [Any]:
            let items = list.compactMap { format($0) }
            if items.isEmpty { return nil }
            let shown = items.prefix(listLimit).joined(separator: ", ")
            return items.count > listLimit ? shown + ", … (\(items.count) values)" : shown
        default:
            return nil
        }
    }

    private static func numberText(_ v: Double, integer: Bool) -> String {
        if integer || v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
        return v.formatted(.number.precision(.significantDigits(1...7)).grouping(.never))
    }

    /// Entries whose name or value contains [query] (ignoring case and accents), dropping groups left empty. An empty
    /// query keeps everything; a group whose own name matches stays whole.
    public static func filter(_ groups: [MetadataGroup], query: String) -> [MetadataGroup] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return groups }
        func matches(_ s: String) -> Bool { s.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        return groups.compactMap { group in
            if matches(group.name) { return group }
            let kept = group.entries.filter { matches($0.name) || matches($0.value) }
            return kept.isEmpty ? nil : MetadataGroup(name: group.name, entries: kept)
        }
    }

    /// The list as plain text ("Group", then "Name: value" lines), for the clipboard.
    public static func text(_ groups: [MetadataGroup]) -> String {
        groups.map { g in
            ([g.name] + g.entries.map { "\($0.name): \($0.value)" }).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
