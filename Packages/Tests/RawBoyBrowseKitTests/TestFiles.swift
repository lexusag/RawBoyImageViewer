/// Synthetic raw structures for the parser tests: ports of the builders in RawBoy's browse.test.ts and
/// photoorder.test.ts.
enum TestFiles {
    /// A structurally complete JPEG (not decodable): SOF [sof] with the size, a scan with stuffed and restart bytes,
    /// EOI.
    static func jpeg(_ width: Int, _ height: Int, sof: UInt8 = 0xc0, extra: [UInt8] = []) -> [UInt8] {
        [0xff, 0xd8] + extra + [
            0xff, sof, 0x00, 0x0b, 0x08, UInt8(height >> 8), UInt8(height & 255), UInt8(width >> 8),
            UInt8(width & 255), 0x01, 0x01, 0x11, 0x00,
            0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3f, 0x00,
            0x12, 0x34, 0xff, 0x00, 0x56, 0xff, 0xd3, 0x78,
            0xff, 0xd9,
        ]
    }

    /// An APP1 EXIF segment with only an orientation.
    static func exifApp1(_ orientation: UInt8) -> [UInt8] {
        [
            0xff, 0xe1, 0x00, 0x22, 0x45, 0x78, 0x69, 0x66, 0, 0, 0x49, 0x49, 0x2a, 0, 8, 0, 0, 0, 1, 0, 0x12, 0x01, 3,
            0, 1, 0, 0, 0, orientation, 0, 0, 0, 0, 0, 0, 0,
        ]
    }

    typealias Entry = (tag: Int, type: Int, values: [Int])

    /// A little-endian TIFF: IFDs given as entry lists (chained in order), blobs appended after them. Value -(n + 1)
    /// is blob n's offset, -(1000 + n) sub-IFD n's offset.
    static func tiff(_ ifds: [[Entry]], _ blobs: [[UInt8]], subIfds: [[Entry]] = []) -> [UInt8] {
        let all = ifds + subIfds
        var ifdOffsets: [Int] = []
        var at = 8
        for e in all {
            ifdOffsets.append(at)
            at += 2 + e.count * 12 + 4
        }
        var blobOffsets: [Int] = []
        for b in blobs {
            blobOffsets.append(at)
            at += b.count
        }
        var out = [UInt8](repeating: 0, count: at)
        func set16(_ p: Int, _ v: Int) {
            out[p] = UInt8(v & 255)
            out[p + 1] = UInt8((v >> 8) & 255)
        }
        func set32(_ p: Int, _ v: Int) {
            set16(p, v & 0xffff)
            set16(p + 2, (v >> 16) & 0xffff)
        }
        out[0] = 0x49
        out[1] = 0x49
        out[2] = 0x2a
        set32(4, 8)
        func resolve(_ x: Int) -> Int {
            x <= -1000 ? ifdOffsets[ifds.count + (-x - 1000)] : x < 0 ? blobOffsets[-x - 1] : x
        }
        for (k, entries) in all.enumerated() {
            var p = ifdOffsets[k]
            set16(p, entries.count)
            p += 2
            for entry in entries {
                set16(p, entry.tag)
                set16(p + 2, entry.type)
                set32(p + 4, entry.type == 7 ? entry.values[1] : entry.values.count)
                let x = resolve(entry.values[0])
                if entry.type == 3 { set16(p + 8, x) } else { set32(p + 8, x) }
                p += 12
            }
            set32(p, k + 1 < ifds.count ? ifdOffsets[k + 1] : 0)
        }
        for (i, b) in blobs.enumerated() { out.replaceSubrange(blobOffsets[i]..<blobOffsets[i] + b.count, with: b) }
        return out
    }

    static func text(_ s: String) -> [UInt8] { Array(s.utf8) }
    static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8((v >> 8) & 255)] }
    static func le32(_ v: Int) -> [UInt8] { le16(v & 0xffff) + le16((v >> 16) & 0xffff) }
    static func be32(_ v: Int) -> [UInt8] {
        [UInt8((v >> 24) & 255), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)]
    }

    static func hexBytes(_ s: String) -> [UInt8] {
        var out: [UInt8] = []
        var chars = Array(s)
        while chars.count >= 2 {
            out.append(UInt8(String(chars[0..<2]), radix: 16)!)
            chars.removeFirst(2)
        }
        return out
    }

    /// An ISO base media box.
    static func box(_ type: String, _ payload: [UInt8]..., uuid: String = "") -> [UInt8] {
        let u = hexBytes(uuid)
        let body = payload.flatMap { $0 }
        return be32(8 + u.count + body.count) + text(type) + u + body
    }
}
