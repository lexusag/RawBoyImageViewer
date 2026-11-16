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

    /// The keys `write` owns. Every other key of the edits is RawBoy's own and is never touched.
    static let geometryKeys = [
        "rotation", "flipHorizontal", "flipVertical", "cropLeft", "cropTop", "cropRight", "cropBottom",
    ]

    /// [json] (nil: none yet) with [geometry]'s turn, mirror and crop; nil when no edits are left. Only the geometry
    /// keys are edited, in the text: every other key (RawBoy's masks, strokes, curves...) keeps its bytes, order and
    /// number formatting, as a RawBoy web write has them.
    public static func write(_ json: String?, _ geometry: DevelopGeometry) -> String? {
        let c = geometry.crop
        let wanted: [(key: String, raw: String?)] = [
            ("rotation", geometry.rotation == 0 ? nil : String(geometry.rotation)),
            ("flipHorizontal", geometry.mirrored ? "true" : nil),
            ("flipVertical", nil),
            ("cropLeft", c.isFull || c.left <= 0 ? nil : tidy(c.left)),
            ("cropTop", c.isFull || c.top <= 0 ? nil : tidy(c.top)),
            ("cropRight", c.isFull || c.right >= 1 ? nil : tidy(c.right)),
            ("cropBottom", c.isFull || c.bottom >= 1 ? nil : tidy(c.bottom)),
        ]
        guard var text = json, values(text) != nil else { return fresh(wanted) }
        for (key, raw) in wanted {
            guard let next = JSONMembers.set(text, in: "values", key: key, raw: raw) else { return fresh(wanted) }
            text = next
        }
        return JSONMembers.isEmpty(text, in: "values") == true ? nil : text
    }

    /// Edits holding just [wanted] (nil: none left), as RawBoy writes a first one.
    private static func fresh(_ wanted: [(key: String, raw: String?)]) -> String? {
        let members = wanted.compactMap { w in w.raw.map { "\"\(w.key)\":\($0)" } }
        guard !members.isEmpty else { return nil }
        return #"{"format":"\#(format)","version":\#(version),"values":{"# + members.joined(separator: ",") + "}}"
    }

    /// [v] to 6 decimals, written as such ("0.65", not "0.65000000000000002"): far below a pixel.
    static func tidy(_ v: Double) -> String {
        var s = String(format: "%.6f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    static func values(_ json: String) -> [String: Any]? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
            object["format"] as? String == format
        else { return nil }
        return object["values"] as? [String: Any] ?? [:]
    }
}

/// Edits of one member of a JSON object nested in the document's top-level object, made in the text so that nothing
/// else in it changes by a byte. Just enough JSON scanning for that; text that doesn't scan answers nil.
enum JSONMembers {
    struct Member {
        var key: String
        var start: Int  // the key's opening quote
        var valueStart: Int
        var valueEnd: Int
    }

    /// [text] with member [key] of the object [container] (a member of the top-level object) set to the JSON [raw]
    /// (nil removes it). A value that already means [raw] is left as it is.
    static func set(_ text: String, in container: String, key: String, raw: String?) -> String? {
        let bytes = Array(text.utf8)
        guard let top = members(bytes, objectAt: skipSpace(bytes, 0)),
            let box = top.members.first(where: { $0.key == container }), bytes[box.valueStart] == UInt8(ascii: "{"),
            let inner = members(bytes, objectAt: box.valueStart)
        else { return nil }
        let at = inner.members.firstIndex { $0.key == key }
        func make(_ edit: (inout [UInt8]) -> Void) -> String {
            var out = bytes
            edit(&out)
            return String(decoding: out, as: UTF8.self)
        }
        switch (at, raw) {
        case (nil, nil): return text
        case (let i?, let raw?):
            let m = inner.members[i]
            let old = String(decoding: bytes[m.valueStart..<m.valueEnd], as: UTF8.self)
            if old == raw || sameNumber(old, raw) { return text }
            return make { $0.replaceSubrange(m.valueStart..<m.valueEnd, with: Array(raw.utf8)) }
        case (let i?, nil):
            let all = inner.members
            let m = all[i]
            if i + 1 < all.count { return make { $0.removeSubrange(m.start..<all[i + 1].start) } }
            if i > 0 { return make { $0.removeSubrange(all[i - 1].valueEnd..<m.valueEnd) } }
            return make { $0.removeSubrange(m.start..<m.valueEnd) }
        case (nil, let raw?):
            let member = Array("\"\(key)\":\(raw)".utf8)
            if let last = inner.members.last {
                return make { $0.insert(contentsOf: [UInt8(ascii: ",")] + member, at: last.valueEnd) }
            }
            return make { $0.insert(contentsOf: member, at: inner.open + 1) }
        }
    }

    /// Whether the object [container] has no members, or nil when [text] doesn't scan.
    static func isEmpty(_ text: String, in container: String) -> Bool? {
        let bytes = Array(text.utf8)
        guard let top = members(bytes, objectAt: skipSpace(bytes, 0)),
            let box = top.members.first(where: { $0.key == container }), bytes[box.valueStart] == UInt8(ascii: "{"),
            let inner = members(bytes, objectAt: box.valueStart)
        else { return nil }
        return inner.members.isEmpty
    }

    private static func sameNumber(_ a: String, _ b: String) -> Bool {
        guard let x = Double(a), let y = Double(b) else { return false }
        return x == y
    }

    private static func skipSpace(_ b: [UInt8], _ from: Int) -> Int {
        var i = from
        while i < b.count, b[i] == 0x20 || b[i] == 0x0A || b[i] == 0x0D || b[i] == 0x09 { i += 1 }
        return i
    }

    /// The end (exclusive) of the string starting at the quote [from].
    private static func stringEnd(_ b: [UInt8], _ from: Int) -> Int? {
        var i = from + 1
        while i < b.count {
            if b[i] == UInt8(ascii: "\\") { i += 2; continue }
            if b[i] == UInt8(ascii: "\"") { return i + 1 }
            i += 1
        }
        return nil
    }

    /// The end (exclusive) of the value starting at [from].
    private static func valueEnd(_ b: [UInt8], _ from: Int) -> Int? {
        guard from < b.count else { return nil }
        switch b[from] {
        case UInt8(ascii: "\""): return stringEnd(b, from)
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            var i = from
            while i < b.count {
                switch b[i] {
                case UInt8(ascii: "\""):
                    guard let e = stringEnd(b, i) else { return nil }
                    i = e
                    continue
                case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    depth -= 1
                    if depth == 0 { return i + 1 }
                default: break
                }
                i += 1
            }
            return nil
        default:
            var i = from
            while i < b.count, !",}] \n\r\t".utf8.contains(b[i]) { i += 1 }
            return i > from ? i : nil
        }
    }

    /// The members of the object whose `{` is at [open].
    private static func members(_ b: [UInt8], objectAt open: Int) -> (open: Int, members: [Member])? {
        guard open < b.count, b[open] == UInt8(ascii: "{") else { return nil }
        var out: [Member] = []
        var i = skipSpace(b, open + 1)
        if i < b.count, b[i] == UInt8(ascii: "}") { return (open, out) }
        while i < b.count, b[i] == UInt8(ascii: "\"") {
            guard let keyEnd = stringEnd(b, i) else { return nil }
            let key = String(decoding: b[(i + 1)..<(keyEnd - 1)], as: UTF8.self)
            var j = skipSpace(b, keyEnd)
            guard j < b.count, b[j] == UInt8(ascii: ":") else { return nil }
            j = skipSpace(b, j + 1)
            guard let end = valueEnd(b, j) else { return nil }
            out.append(Member(key: key, start: i, valueStart: j, valueEnd: end))
            i = skipSpace(b, end)
            guard i < b.count else { return nil }
            if b[i] == UInt8(ascii: "}") { return (open, out) }
            guard b[i] == UInt8(ascii: ",") else { return nil }
            i = skipSpace(b, i + 1)
        }
        return nil
    }
}
