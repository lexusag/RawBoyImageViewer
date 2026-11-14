import Foundation

/// The geometry part of RawBoy's edits JSON (`rawboy:Develop`, RawBoy's `develop/Edits.ts`): what a viewer reads and
/// writes so RawBoy opens the photo turned and cropped the same way. Every other field is kept exactly; fields at
/// their as-shot defaults are left out, as RawBoy does (no edits at all: no JSON).
public struct DevelopGeometry: Equatable, Sendable {
    /// Clockwise quarter turns on top of the file's own orientation.
    public var rotation = 0
    /// Mirrored left-right before turning (RawBoy's flipVertical is folded in: top-bottom = left-right + half turn).
    public var mirrored = false
    public var crop = CropRect.full
    /// RawBoy straightened or corrected the perspective: its frame isn't the plain turned photo, so the viewer leaves
    /// cropping it to RawBoy.
    public var isStraightened = false

    public init(rotation: Int = 0, mirrored: Bool = false, crop: CropRect = .full, isStraightened: Bool = false) {
        self.rotation = ((rotation % 4) + 4) % 4
        self.mirrored = mirrored
        self.crop = crop
        self.isStraightened = isStraightened
    }

    /// The turn and mirror as an orientation on top of the file's.
    public var orientation: Orientation { Orientation(mirrored: mirrored, quarterTurns: rotation) }
}

public enum DevelopEdits {
    public static let format = "rawboy-edit"
    public static let version = 1

    /// The geometry in RawBoy's edits JSON [json], or nil when it isn't RawBoy's.
    public static func geometry(_ json: String) -> DevelopGeometry? {
        guard let values = values(json) else { return nil }
        func number(_ key: String) -> Double? { (values[key] as? NSNumber)?.doubleValue }
        func flag(_ key: String) -> Bool { (values[key] as? Bool) ?? false }
        let flipV = flag("flipVertical")
        let rotation = Int((number("rotation") ?? 0).rounded()) + (flipV ? 2 : 0)
        let crop = CropRect(
            left: number("cropLeft") ?? 0, top: number("cropTop") ?? 0, right: number("cropRight") ?? 1,
            bottom: number("cropBottom") ?? 1)
        let straightened =
            (number("straighten") ?? 0) != 0 || (number("perspectiveVertical") ?? 0) != 0
            || (number("perspectiveHorizontal") ?? 0) != 0
        return DevelopGeometry(
            rotation: rotation, mirrored: flag("flipHorizontal") != flipV, crop: crop, isStraightened: straightened)
    }

    /// [json] (nil: none yet) with [geometry]'s turn, mirror and crop; nil when no edits are left.
    public static func write(_ json: String?, _ geometry: DevelopGeometry) -> String? {
        var values = json.flatMap(values) ?? [:]
        func set(_ key: String, _ value: Any?) {
            if let value { values[key] = value } else { values.removeValue(forKey: key) }
        }
        set("rotation", geometry.rotation == 0 ? nil : geometry.rotation)
        set("flipHorizontal", geometry.mirrored ? true : nil)
        set("flipVertical", nil)
        let c = geometry.crop
        set("cropLeft", c.isFull || c.left <= 0 ? nil : tidy(c.left))
        set("cropTop", c.isFull || c.top <= 0 ? nil : tidy(c.top))
        set("cropRight", c.isFull || c.right >= 1 ? nil : tidy(c.right))
        set("cropBottom", c.isFull || c.bottom >= 1 ? nil : tidy(c.bottom))
        guard !values.isEmpty else { return nil }
        let object: [String: Any] = ["format": format, "version": version, "values": values]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// [v] to 6 decimals, written as such ("0.65", not "0.65000000000000002"): far below a pixel.
    static func tidy(_ v: Double) -> NSDecimalNumber {
        NSDecimalNumber(string: String(format: "%.6f", v)).rounding(
            accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain, scale: 6, raiseOnExactness: false, raiseOnOverflow: false,
                raiseOnUnderflow: false, raiseOnDivideByZero: false))
    }

    static func values(_ json: String) -> [String: Any]? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
            object["format"] as? String == format
        else { return nil }
        return object["values"] as? [String: Any] ?? [:]
    }
}

extension XmpSidecar {
    /// RawBoy's edits (`rawboy:Develop`, escaped JSON) in a sidecar's text, or nil.
    public static func readDevelop(_ text: String) -> String? {
        fieldValue(text, "rawboy:Develop").map(unescapeXml)
    }

    /// [text] (nil: a new sidecar) with RawBoy's edits set to [json]; nil removes them.
    public static func writeDevelop(_ text: String?, _ json: String?) throws -> String {
        try setField(text ?? empty, "rawboy:Develop", "rawboy", rawboyNS, json.map(escapeXml))
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
            switch entity {
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
