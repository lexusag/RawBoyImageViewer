/// When a photo was shot, for ordering the browser: EXIF's DateTimeOriginal (else when it was digitised or last
/// written), found as `EmbeddedPreviews` finds previews, reading only the bytes needed, never decoding the raw.
/// A port of RawBoy's `CaptureDate.ts`: keep the two in step.
///
/// - TIFF-based raws (DNG, CR2, NEF, ARW, ORF, RW2, PEF...): IFD0's EXIF IFD, else IFD0's DateTime.
/// - CR3: CMT2 (the EXIF IFD), else CMT1 (IFD0).
/// - RAF and JPEG: the JPEG's APP1 EXIF (a RAF's embedded JPEG carries the camera's EXIF).
/// - Anything else (HEIC, PNG): nil; callers fall back to the file's date.
public enum CaptureDate {
    /// The capture date as an EXIF date ("YYYY:MM:DD HH:MM:SS", sorts as text), or nil.
    public static func find(in source: ByteSource) -> String? {
        let head = source.read(0, 16)
        guard head.count >= 16 else { return nil }
        if head.ascii(0, 15) == "FUJIFILMCCD-RAW" { return jpegDate(source, source.u32(84, false)) }
        if head.ascii(4, 8) == "ftyp" { return cr3Date(source) }
        if EmbeddedPreviews.isTiff(head) { return tiffDate(source, 0) }
        if head[0] == 0xff && head[1] == 0xd8 { return jpegDate(source, 0) }
        return nil
    }

    static let tagDateTime = 0x0132
    static let tagExifIFD = 0x8769
    static let tagDateTimeOriginal = 0x9003
    static let tagDateTimeDigitized = 0x9004

    struct IFD {
        let bytes: [UInt8]
        /// Tag → entry offset in [bytes].
        let tags: [Int: Int]
    }

    /// The IFD at [at] (relative to [base]); nil when it isn't one.
    static func readIFD(_ source: ByteSource, _ base: Int, _ at: Int, _ le: Bool) -> IFD? {
        guard at != 0, base + at + 2 <= source.size else { return nil }
        let n = source.u16(base + at, le)
        guard n > 0, n <= 1000 else { return nil }
        let bytes = source.read(base + at + 2, n * 12)
        var tags: [Int: Int] = [:]
        var i = 0
        while i < n && i * 12 + 12 <= bytes.count {
            tags[bytes.u16(i * 12, le)] = i * 12
            i += 1
        }
        return IFD(bytes: bytes, tags: tags)
    }

    /// ASCII entry [tag] as a valid EXIF date, else nil.
    static func date(_ source: ByteSource, _ base: Int, _ ifd: IFD, _ tag: Int, _ le: Bool) -> String? {
        guard let p = ifd.tags[tag], ifd.bytes.u16(p + 2, le) == 2, ifd.bytes.u32(p + 4, le) >= 19 else { return nil }
        // 20 bytes with its NUL, so never inline in the entry.
        let bytes = source.read(base + ifd.bytes.u32(p + 8, le), 19)
        return bytes.count == 19 ? PhotoOrder.validDate(bytes.ascii(0, 19)) : nil
    }

    /// The date in the TIFF structure at [base]: the EXIF IFD's capture date, else IFD0's DateTime.
    static func tiffDate(_ source: ByteSource, _ base: Int) -> String? {
        let header = source.read(base, 8)
        let le = header.u8(0) == 0x49
        guard let ifd0 = readIFD(source, base, header.u32(4, le), le) else { return nil }
        if let exifAt = ifd0.tags[tagExifIFD], let exif = readIFD(source, base, ifd0.bytes.u32(exifAt + 8, le), le) {
            if let d = date(source, base, exif, tagDateTimeOriginal, le)
                ?? date(source, base, exif, tagDateTimeDigitized, le)
            {
                return d
            }
        }
        return date(source, base, ifd0, tagDateTime, le)
    }

    /// The date in the EXIF segment of the JPEG at [offset], else nil.
    static func jpegDate(_ source: ByteSource, _ offset: Int) -> String? {
        guard source.u16(offset, false) == 0xffd8 else { return nil }
        var at = offset + 2
        var i = 0
        while i < 32 && at + 4 <= source.size {
            i += 1
            let m = source.read(at, 4)
            guard m.u8(0) == 0xff else { return nil }
            let marker = m.u8(1)
            if marker == 0xda || marker == 0xd9 { return nil }
            let size = m.u16(2, false)
            if marker == 0xe1 && size > 16 && source.read(at + 4, 4).ascii(0, 4) == "Exif" {
                return tiffDate(source, at + 10)
            }
            at += 2 + size
        }
        return nil
    }

    /// Canon CR3: moov's Canon box holds CMT1 (IFD0) and CMT2 (the EXIF IFD), each a little TIFF.
    static func cr3Date(_ source: ByteSource) -> String? {
        guard let moov = EmbeddedPreviews.boxes(source, 0, source.size).first(where: { $0.type == "moov" }),
            let canon = EmbeddedPreviews.boxes(source, moov.start, moov.end)
                .first(where: { $0.type == "uuid" && $0.uuid == EmbeddedPreviews.canonUUID })
        else { return nil }
        let inner = EmbeddedPreviews.boxes(source, canon.start, canon.end)
        func first(_ start: Int, _ tags: [Int]) -> String? {
            let header = source.read(start, 8)
            let le = header.u8(0) == 0x49
            guard let ifd = readIFD(source, start, header.u32(4, le), le) else { return nil }
            return tags.lazy.compactMap { date(source, start, ifd, $0, le) }.first
        }
        if let cmt2 = inner.first(where: { $0.type == "CMT2" }),
            let d = first(cmt2.start, [tagDateTimeOriginal, tagDateTimeDigitized])
        {
            return d
        }
        return inner.first(where: { $0.type == "CMT1" }).flatMap { first($0.start, [tagDateTime]) }
    }
}
