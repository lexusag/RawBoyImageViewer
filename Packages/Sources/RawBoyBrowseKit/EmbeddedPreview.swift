/// The JPEG preview a camera embedded in its raw file, found without decoding the raw, so a folder of raws opens in
/// seconds. A port of RawBoy Browser's `EmbeddedPreview.ts`: keep the two in step.
///
/// - TIFF-based raws (DNG, CR2, NEF, ARW, PEF, ORF, RW2, SRW, 3FR, ERF, ...): every IFD (IFD0's chain and SubIFDs) is
///   searched for JPEGInterchangeFormat, single-strip JPEG data and RW2's JpgFromRaw.
/// - CR3: track 1 (the full-size JPEG) and the PRVW preview; orientation from CMT1.
/// - RAF: the JPEG offset in the header.
/// - Anything else, or when the above find nothing: a scan of the file's start for JPEG streams.
///
/// Only baseline/progressive JPEGs count (raws keep their sensor data as lossless JPEG too); the largest wins.
/// Not ported yet: DNG 1.7 JPEG XL previews (`findJxlPreview`); ImageIO decodes those DNGs itself.
public struct EmbeddedPreview: Equatable, Sendable {
    /// Where the JPEG is in the file.
    public let offset: Int
    public let length: Int
    /// Size of the JPEG as stored (before orientation).
    public let width: Int
    public let height: Int
    /// The EXIF orientation inside the JPEG, 0 if it has none.
    public let jpegOrientation: Int
    /// The raw's own orientation (IFD0, CR3's CMT1), 0 if none.
    public let rawOrientation: Int

    /// The JPEG's bytes, with an EXIF orientation added when the raw's orientation applies (the JPEG's own wins:
    /// Fujifilm's carries one), so decoders show it upright.
    public func jpeg(from source: ByteSource) -> [UInt8] {
        let bytes = source.read(offset, length)
        return jpegOrientation == 0 && rawOrientation > 1
            ? EmbeddedPreviews.withOrientation(bytes, rawOrientation) : bytes
    }
}

public enum EmbeddedPreviews {
    public struct Candidate: Equatable, Sendable {
        public let offset: Int
        public let length: Int

        public init(offset: Int, length: Int) {
            self.offset = offset
            self.length = length
        }
    }

    struct JpegInfo {
        let width: Int
        let height: Int
        let orientation: Int
    }

    /// How much of a file's start the fallback scan reads.
    static let scanBytes = 16 << 20

    /// The largest embedded preview of [source], or nil if there is none.
    public static func find(in source: ByteSource) -> EmbeddedPreview? {
        let head = source.read(0, 16)
        var candidates: [Candidate] = []
        var orientation = 0
        if head.ascii(0, 15) == "FUJIFILMCCD-RAW" {
            let v = source.read(84, 8)
            candidates.append(Candidate(offset: v.u32(0, false), length: v.u32(4, false)))
        } else if head.ascii(4, 8) == "ftyp" {
            (candidates, orientation) = cr3Candidates(source)
        } else if isTiff(head) {
            (candidates, orientation) = tiffCandidates(source, base: 0)
        }
        var best = largest(source, candidates)
        if best == nil { best = largest(source, scanForJpegs(source.read(0, scanBytes))) }
        guard let (candidate, info) = best else { return nil }
        return EmbeddedPreview(
            offset: candidate.offset, length: candidate.length, width: info.width, height: info.height,
            jpegOrientation: info.orientation, rawOrientation: orientation)
    }

    /// The candidate holding the biggest real (not lossless) JPEG.
    static func largest(_ source: ByteSource, _ candidates: [Candidate]) -> (Candidate, JpegInfo)? {
        var best: (Candidate, JpegInfo)?
        for c in candidates {
            guard c.length >= 20, c.offset >= 0, c.offset + c.length <= source.size,
                let info = jpegInfo(source, c.offset, c.length)
            else { continue }
            if best == nil || info.width * info.height > best!.1.width * best!.1.height { best = (c, info) }
        }
        return best
    }

    /// II/MM followed by 42, or the magics Olympus (ORF: "RO", "RS") and Panasonic (RW2: 0x55) use instead.
    public static func isTiff(_ b: [UInt8]) -> Bool {
        guard b.count >= 4 else { return false }
        let le = b[0] == 0x49 && b[1] == 0x49
        let be = b[0] == 0x4d && b[1] == 0x4d
        guard le || be else { return false }
        let magic = b.u16(2, le)
        return magic == 42 || magic == 0x4f52 || magic == 0x5352 || magic == 0x55
    }

    static let tagOrientation = 274
    static let tagCompression = 259
    static let tagStripOffsets = 273
    static let tagStripByteCounts = 279
    static let tagSubIFDs = 330
    static let tagJpegOffset = 513
    static let tagJpegLength = 514
    static let tagRW2Jpeg = 0x2e

    /// Bytes per value of each TIFF type.
    static let typeSize: [Int: Int] = [
        1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, 8: 2, 9: 4, 10: 8, 11: 4, 12: 8, 13: 4,
    ]

    /// Preview candidates of the TIFF structure at [base] (offsets in it are relative to [base]) and IFD0's
    /// orientation (0 if none).
    static func tiffCandidates(_ source: ByteSource, base: Int) -> ([Candidate], Int) {
        let header = source.read(base, 8)
        let le = header.u8(0) == 0x49
        var candidates: [Candidate] = []
        var orientation = 0
        var queue = [header.u32(4, le)]
        var seen = Set<Int>()
        var first = true
        while !queue.isEmpty && seen.count < 32 {
            let at = queue.removeFirst()
            if at == 0 || seen.contains(at) || base + at + 2 > source.size { continue }
            seen.insert(at)
            let n = source.u16(base + at, le)
            if n == 0 || n > 1000 { continue }
            let ifd = source.read(base + at + 2, n * 12 + 4)

            func values(_ i: Int, max: Int = 64) -> [Int] {
                let p = i * 12
                let type = ifd.u16(p + 2, le)
                let count = ifd.u32(p + 4, le)
                guard type == 3 || type == 4 || type == 13 else { return [] }
                let size = typeSize[type] ?? 1
                let wanted = min(count, max)
                let data =
                    size * count <= 4
                    ? Array(ifd[min(p + 8, ifd.count)..<min(p + 12, ifd.count)])
                    : source.read(base + ifd.u32(p + 8, le), size * wanted)
                return (0..<wanted).map { k in type == 3 ? data.u16(k * 2, le) : data.u32(k * 4, le) }
            }
            var tags: [Int: Int] = [:]
            for i in 0..<n { tags[ifd.u16(i * 12, le)] = i }
            func one(_ tag: Int) -> Int? { tags[tag].flatMap { values($0).first } }

            if first { orientation = one(tagOrientation) ?? 0 }
            first = false
            if let offset = one(tagJpegOffset), let length = one(tagJpegLength), offset != 0, length != 0 {
                candidates.append(Candidate(offset: base + offset, length: length))
            }
            let compression = one(tagCompression)
            if compression == 6 || compression == 7 {
                let offsets = tags[tagStripOffsets].map { values($0) } ?? []
                let counts = tags[tagStripByteCounts].map { values($0) } ?? []
                if offsets.count == 1 && counts.count == 1 {
                    candidates.append(Candidate(offset: base + offsets[0], length: counts[0]))
                }
            }
            if let i = tags[tagRW2Jpeg] {
                let count = ifd.u32(i * 12 + 4, le)
                if count > 4 { candidates.append(Candidate(offset: base + ifd.u32(i * 12 + 8, le), length: count)) }
            }
            if let i = tags[tagSubIFDs] { queue.append(contentsOf: values(i)) }
            queue.append(ifd.u32(n * 12, le))
        }
        return (candidates, orientation)
    }

    static let canonUUID = "85c0b687820f11e08111f4ce462b6a48"
    static let canonPreviewUUID = "eaf42b5e1c984b88b9fbb7dc406e4d16"

    public struct Box: Equatable, Sendable {
        public let type: String
        /// Start of the box's payload (after the header and, for uuid boxes, the 16-byte uuid).
        public let start: Int
        public let end: Int
        public let uuid: String
    }

    /// The boxes of an ISO base media file between [from] and [to].
    public static func boxes(_ source: ByteSource, _ from: Int, _ to: Int) -> [Box] {
        var out: [Box] = []
        var at = from
        while at + 8 <= to && out.count < 256 {
            let h = source.read(at, 32)
            guard h.count >= 8 else { break }
            var size = h.u32(0, false)
            let type = h.ascii(4, 8)
            var header = 8
            if size == 1 {
                size = Int(min(h.u64be(8), UInt64(Int.max / 2)))
                header = 16
            } else if size == 0 {
                size = to - at
            }
            if size < header { break }
            var uuid = ""
            if type == "uuid" {
                uuid = (header..<header + 16).map { hex(h.u8($0)) }.joined()
                header += 16
            }
            out.append(Box(type: type, start: at + header, end: min(at + size, to), uuid: uuid))
            if size > to - at { break }
            at += size
        }
        return out
    }

    private static func hex(_ byte: Int) -> String {
        let digits = Array("0123456789abcdef")
        return String([digits[(byte >> 4) & 15], digits[byte & 15]])
    }

    /// Canon CR3: track 1's full-size JPEG and the PRVW preview; orientation from CMT1 (a TIFF with IFD0).
    static func cr3Candidates(_ source: ByteSource) -> ([Candidate], Int) {
        var candidates: [Candidate] = []
        var orientation = 0
        let top = boxes(source, 0, source.size)
        if let moov = top.first(where: { $0.type == "moov" }) {
            let inner = boxes(source, moov.start, moov.end)
            if let canon = inner.first(where: { $0.type == "uuid" && $0.uuid == canonUUID }),
                let cmt1 = boxes(source, canon.start, canon.end).first(where: { $0.type == "CMT1" })
            {
                orientation = tiffCandidates(source, base: cmt1.start).1
            }
            if let trak = inner.first(where: { $0.type == "trak" }),
                let stbl = descend(source, trak, ["mdia", "minf", "stbl"])
            {
                let parts = boxes(source, stbl.start, stbl.end)
                let stsz = parts.first { $0.type == "stsz" }
                let co64 = parts.first { $0.type == "co64" }
                let stco = parts.first { $0.type == "stco" }
                if let stsz, co64 != nil || stco != nil {
                    let sz = source.read(stsz.start, 16)
                    let length = sz.u32(4, false) != 0 ? sz.u32(4, false) : sz.u32(12, false)
                    let offset =
                        co64.map { Int(min(source.read($0.start + 8, 8).u64be(0), UInt64(Int.max / 2))) }
                        ?? source.u32(stco!.start + 8, false)
                    candidates.append(Candidate(offset: offset, length: length))
                }
            }
        }
        if let preview = top.first(where: { $0.type == "uuid" && $0.uuid == canonPreviewUUID }),
            // 8 bytes, then the PRVW box: header, 12 bytes of fields, the JPEG's length, the JPEG.
            let prvw = boxes(source, preview.start + 8, preview.end).first(where: { $0.type == "PRVW" })
        {
            candidates.append(Candidate(offset: prvw.start + 16, length: source.u32(prvw.start + 12, false)))
        }
        return (candidates, orientation)
    }

    static func descend(_ source: ByteSource, _ box: Box, _ path: [String]) -> Box? {
        var at: Box? = box
        for type in path {
            guard let current = at else { return nil }
            at = boxes(source, current.start, current.end).first { $0.type == type }
        }
        return at
    }

    /// Size and orientation of the JPEG at [offset], read from its markers up to the frame header; nil when it isn't
    /// a baseline, extended or progressive JPEG (a lossless one is raw sensor data).
    static func jpegInfo(_ source: ByteSource, _ offset: Int, _ length: Int) -> JpegInfo? {
        let end = offset + length
        guard source.u16(offset, false) == 0xffd8 else { return nil }
        var at = offset + 2
        var orientation = 0
        var i = 0
        while i < 64 && at + 4 <= end {
            i += 1
            let m = source.read(at, 4)
            guard m.count == 4, m[0] == 0xff else { return nil }
            let marker = Int(m[1])
            if marker == 0xff {
                at += 1  // fill byte
                continue
            }
            let size = m.u16(2, false)
            if marker == 0xc0 || marker == 0xc1 || marker == 0xc2 {
                let f = source.read(at + 4, 5)
                let height = f.u16(1, false)
                let width = f.u16(3, false)
                return width > 0 && height > 0 ? JpegInfo(width: width, height: height, orientation: orientation) : nil
            }
            if (0xc3...0xcf).contains(marker) && ![0xc4, 0xc8, 0xcc].contains(marker) || marker == 0xda { return nil }
            if marker == 0xe1 && orientation == 0 && size > 16 {
                let app1 = source.read(at + 4, min(size, 4096) - 2)
                if app1.ascii(0, 4) == "Exif" { orientation = tiffOrientation(Array(app1.dropFirst(6))) }
            }
            at += 2 + size
        }
        return nil
    }

    /// IFD0's Orientation in the TIFF bytes [b] (an EXIF payload), 0 if absent.
    public static func tiffOrientation(_ b: [UInt8]) -> Int {
        guard b.count >= 8, isTiff(b) else { return 0 }
        let le = b[0] == 0x49
        let ifd = b.u32(4, le)
        guard ifd + 2 <= b.count else { return 0 }
        let n = b.u16(ifd, le)
        var i = 0
        while i < n && ifd + 2 + i * 12 + 12 <= b.count {
            let p = ifd + 2 + i * 12
            if b.u16(p, le) == tagOrientation { return b.u16(p + 8, le) }
            i += 1
        }
        return 0
    }

    /// Complete baseline/progressive JPEG streams in [b]: from SOI through the markers to the scan, then the
    /// entropy-coded data up to EOI (thumbnails inside APP segments are skipped with their segment).
    public static func scanForJpegs(_ b: [UInt8]) -> [Candidate] {
        var found: [Candidate] = []
        var i = 0
        while i + 4 < b.count && found.count < 16 {
            guard b[i] == 0xff && b[i + 1] == 0xd8 && b[i + 2] == 0xff else {
                i += 1
                continue
            }
            let end = jpegEnd(b, i)
            if end > 0 {
                found.append(Candidate(offset: i, length: end - i))
                i = end
            } else {
                i += 2
            }
        }
        return found
    }

    /// The offset after the EOI of the JPEG starting at [start] in [b], or -1 if it isn't a complete one.
    static func jpegEnd(_ b: [UInt8], _ start: Int) -> Int {
        var at = start + 2
        var frame = false
        while at + 4 <= b.count {
            if b[at] != 0xff { return -1 }
            let marker = Int(b[at + 1])
            if marker == 0xff {
                at += 1
                continue
            }
            let size = b.u16(at + 2, false)
            if marker == 0xc0 || marker == 0xc1 || marker == 0xc2 {
                frame = true
            } else if (0xc3...0xcf).contains(marker) && ![0xc4, 0xc8, 0xcc].contains(marker) {
                return -1
            }
            at += 2 + size
            if marker != 0xda { continue }
            if !frame { return -1 }
            // Entropy-coded data: FF 00 is a stuffed byte and FF D0-D7 restart markers; other markers end the scan
            // (progressive JPEGs have several scans).
            while at + 1 < b.count {
                if b[at] != 0xff {
                    at += 1
                    continue
                }
                let next = Int(b[at + 1])
                if next == 0x00 || (0xd0...0xd7).contains(next) || next == 0xff {
                    at += next == 0xff ? 1 : 2
                    continue
                }
                if next == 0xd9 { return at + 2 }
                break  // another segment (DHT, SOS...) follows
            }
        }
        return -1
    }

    /// [jpeg] with an APP1 EXIF segment holding only [orientation] inserted after SOI.
    public static func withOrientation(_ jpeg: [UInt8], _ orientation: Int) -> [UInt8] {
        let app1: [UInt8] = [
            0xff, 0xe1, 0x00, 0x22,  // APP1, length 34
            0x45, 0x78, 0x69, 0x66, 0x00, 0x00,  // "Exif\0\0"
            0x4d, 0x4d, 0x00, 0x2a, 0x00, 0x00, 0x00, 0x08,  // big-endian TIFF, IFD0 at 8
            0x00, 0x01,  // one entry
            0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, UInt8(orientation & 0xff), 0x00, 0x00,  // Orientation
            0x00, 0x00, 0x00, 0x00,  // no next IFD
        ]
        return Array(jpeg.prefix(2)) + app1 + Array(jpeg.dropFirst(2))
    }
}
