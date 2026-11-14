import Foundation
import RawBoyBrowseKit
import Testing

/// The cases of RawBoy's photoorder.test.ts and PhotoOrderTests.swift.
struct PhotoOrderTests {
    let photos: [(date: String?, name: String)] = [
        ("2026:10:01 12:00:00", "IMG_10.CR3"),
        ("2026:10:01 12:00:05", "img_9.CR3"),
        (nil, "DSCF0001.RAF"),
        ("2026:09:30 08:00:00", "IMG_2.CR3"),
        (nil, "A.dng"),
    ]

    @Test func byDateThenUndatedByName() {
        let order = photos.sorted { PhotoOrder.inOrder(.date, $0, $1) }.map(\.name)
        #expect(order == ["IMG_2.CR3", "IMG_10.CR3", "img_9.CR3", "A.dng", "DSCF0001.RAF"])
    }

    @Test func byNameWithNumbersByValue() {
        let order = photos.sorted { PhotoOrder.inOrder(.name, $0, $1) }.map(\.name)
        #expect(order == ["A.dng", "DSCF0001.RAF", "IMG_2.CR3", "img_9.CR3", "IMG_10.CR3"])
    }

    @Test func validDates() {
        #expect(PhotoOrder.validDate("2026:10:01 12:00:00\0") == "2026:10:01 12:00:00")
        #expect(PhotoOrder.validDate("0000:00:00 00:00:00") == nil)
        #expect(PhotoOrder.validDate("    :  :     :  :  ") == nil)
        #expect(
            PhotoOrder.fileDate(Date(timeIntervalSince1970: 1_792_599_059), timeZone: TimeZone(identifier: "UTC")!)
                == "2026:10:21 16:10:59")
        #expect(PhotoOrder.fileDate(nil) == nil)
    }
}

struct CaptureDateTests {
    typealias T = TestFiles

    /// A little-endian TIFF: IFD0 with DateTime [ifd0Date] and, when given, an EXIF IFD with DateTimeOriginal.
    static func tiff(_ ifd0Date: String, _ exifDate: String? = nil) -> [UInt8] {
        let d0: [UInt8] = T.text(ifd0Date) + [0]
        let d1: [UInt8] = exifDate.map { (date: String) -> [UInt8] in T.text(date) + [0] } ?? []
        let n0 = exifDate != nil ? 2 : 1
        let ifd0At = 8
        let exifAt = ifd0At + 2 + n0 * 12 + 4
        let exifSize = exifDate != nil ? 2 + 12 + 4 : 0
        let d0At = exifAt + exifSize
        let d1At = d0At + d0.count
        var out: [UInt8] = [0x49, 0x49, 42, 0] + T.le32(ifd0At) + T.le16(n0)
        out += T.le16(0x0132) + T.le16(2)
        out += T.le32(d0.count) + T.le32(d0At)
        if exifDate != nil {
            out += T.le16(0x8769) + T.le16(4)
            out += T.le32(1) + T.le32(exifAt)
        }
        out += T.le32(0)
        if exifDate != nil {
            out += T.le16(1) + T.le16(0x9003) + T.le16(2)
            out += T.le32(d1.count) + T.le32(d1At) + T.le32(0)
        }
        return out + d0 + d1
    }

    /// A JPEG holding [exif] in APP1 (nothing decodable after it).
    static func jpeg(_ exif: [UInt8]) -> [UInt8] {
        let size = 2 + 6 + exif.count
        return [0xff, 0xd8, 0xff, 0xe1, UInt8(size >> 8), UInt8(size & 255)] + T.text("Exif") + [0, 0] + exif
            + [0xff, 0xda, 0, 2, 0xff, 0xd9]
    }

    func date(_ bytes: [UInt8]) -> String? { CaptureDate.find(in: BytesSource(bytes)) }

    @Test func tiffRawsReadTheExifIfdFirstElseIfd0() {
        #expect(date(Self.tiff("2026:08:15 10:00:00", "2026:08:14 19:03:27")) == "2026:08:14 19:03:27")
        #expect(date(Self.tiff("2026:08:15 10:00:00")) == "2026:08:15 10:00:00")
    }

    @Test func jpegsAndRafsReadTheirJpeg() {
        let j = Self.jpeg(Self.tiff("2026:08:15 10:00:00", "2026:07:01 06:30:00"))
        #expect(date(j) == "2026:07:01 06:30:00")
        var header = [UInt8](repeating: 0, count: 100)
        let magic = T.text("FUJIFILMCCD-RAW 0201")
        header.replaceSubrange(0..<magic.count, with: magic)
        header.replaceSubrange(84..<88, with: T.be32(100))
        #expect(date(header + j) == "2026:07:01 06:30:00")
    }

    @Test func cr3ReadsCmt2ElseCmt1() {
        func cr3(_ cmt: [UInt8]) -> [UInt8] {
            T.box("ftyp", T.text("crx ")) + T.box("moov", T.box("uuid", cmt, uuid: "85c0b687820f11e08111f4ce462b6a48"))
        }
        // Built in steps: older compilers time out type-checking it as one expression.
        var exifIfd: [UInt8] = [0x49, 0x49, 42, 0]
        exifIfd += T.le32(8) + T.le16(1)
        exifIfd += T.le16(0x9003) + T.le16(2)
        exifIfd += T.le32(20) + T.le32(26)
        exifIfd += T.le32(0)
        exifIfd += T.text("2026:05:05 05:05:05") + [0]
        #expect(
            date(cr3(T.box("CMT1", Self.tiff("2026:08:15 10:00:00")) + T.box("CMT2", exifIfd)))
                == "2026:05:05 05:05:05")
        #expect(date(cr3(T.box("CMT1", Self.tiff("2026:08:15 10:00:00")))) == "2026:08:15 10:00:00")
    }

    @Test func nilForFilesWithoutOne() {
        #expect(date([UInt8](repeating: 0, count: 64)) == nil)
        #expect(date([]) == nil)
    }
}
