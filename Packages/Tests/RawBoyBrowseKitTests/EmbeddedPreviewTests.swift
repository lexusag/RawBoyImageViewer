import RawBoyBrowseKit
import Testing

/// The cases of RawBoy's browse.test.ts "Embedded previews" (JPEG XL ones aside: not ported).
struct EmbeddedPreviewTests {
    typealias T = TestFiles

    @Test func picksTheLargestRealJpegAndSkipsLosslessSensorData() throws {
        let thumb = T.jpeg(160, 120)
        let preview = T.jpeg(6000, 4000)
        let sensor = T.jpeg(8000, 5000, sof: 0xc3)
        let file = T.tiff(
            [
                [(259, 3, [6]), (273, 4, [-1]), (274, 3, [1]), (279, 4, [preview.count])],
                [(513, 4, [-2]), (514, 4, [thumb.count])],
                [(259, 3, [7]), (273, 4, [-3]), (279, 4, [sensor.count])],
            ], [preview, thumb, sensor])
        let source = BytesSource(file)
        let p = try #require(EmbeddedPreviews.find(in: source))
        #expect([p.width, p.height] == [6000, 4000])
        #expect(p.jpeg(from: source) == preview)
    }

    @Test func followsSubIFDsAndAddsTheRawOrientation() throws {
        let preview = T.jpeg(3000, 2000)
        let file = T.tiff(
            [[(274, 3, [6]), (330, 4, [-1000])]], [preview],
            subIfds: [[(259, 3, [7]), (273, 4, [-1]), (279, 4, [preview.count])]])
        let source = BytesSource(file)
        let p = try #require(EmbeddedPreviews.find(in: source))
        #expect([p.width, p.height] == [3000, 2000])
        let out = p.jpeg(from: source)
        #expect(out.count == preview.count + 36)
        #expect(EmbeddedPreviews.tiffOrientation(Array(out[12...])) == 6)
        #expect(Array(out[38...]) == Array(preview[2...]))
    }

    @Test func keepsTheJpegsOwnOrientation() throws {
        let preview = T.jpeg(3000, 2000, extra: T.exifApp1(8))
        let file = T.tiff([[(274, 3, [6]), (513, 4, [-1]), (514, 4, [preview.count])]], [preview])
        let source = BytesSource(file)
        let p = try #require(EmbeddedPreviews.find(in: source))
        #expect(p.jpeg(from: source) == preview)
    }

    @Test func readsRW2JpgFromRaw() throws {
        let preview = T.jpeg(1920, 1080)
        var file = T.tiff([[(0x2e, 7, [-1, preview.count])]], [preview])
        file.replaceSubrange(0..<4, with: [0x49, 0x49, 0x55, 0x00])
        let p = try #require(EmbeddedPreviews.find(in: BytesSource(file)))
        #expect([p.width, p.height] == [1920, 1080])
    }

    @Test func readsTheJpegOfARafHeader() throws {
        let preview = T.jpeg(1920, 1280, extra: T.exifApp1(1))
        var file = [UInt8](repeating: 0, count: 200 + preview.count)
        let magic = T.text("FUJIFILMCCD-RAW 0201FF383501")
        file.replaceSubrange(0..<magic.count, with: magic)
        file.replaceSubrange(84..<88, with: T.be32(200))
        file.replaceSubrange(88..<92, with: T.be32(preview.count))
        file.replaceSubrange(200..<200 + preview.count, with: preview)
        let p = try #require(EmbeddedPreviews.find(in: BytesSource(file)))
        #expect([p.width, p.height] == [1920, 1280])
    }

    @Test func readsACr3sFullSizeJpegAndCmt1Orientation() throws {
        let full = T.jpeg(6000, 4000)
        let small = T.jpeg(1620, 1080)
        let cmt1 = T.box("CMT1", T.tiff([[(274, 3, [8])]], []))
        let canon = T.box("uuid", cmt1, uuid: "85c0b687820f11e08111f4ce462b6a48")
        // The JPEG's offset is only known once the layout is: ftyp, moov, preview uuid, then the JPEG.
        func build(_ offset: Int) -> [UInt8] {
            let stsz = T.box("stsz", T.be32(0) + T.be32(full.count) + T.be32(1))
            let co64 = T.box("co64", T.be32(0) + T.be32(1) + T.be32(0) + T.be32(offset))
            let trak = T.box("trak", T.box("mdia", T.box("minf", T.box("stbl", stsz, co64))))
            let moov = T.box("moov", canon, trak)
            let prvw = T.box("PRVW", T.be32(0) + T.be32(0) + T.be32(0) + T.be32(small.count), small)
            let preview = T.box("uuid", [UInt8](repeating: 0, count: 8), prvw, uuid: "eaf42b5e1c984b88b9fbb7dc406e4d16")
            return T.box("ftyp", T.text("crx "), T.be32(1)) + moov + preview
        }
        let head = build(0).count
        let source = BytesSource(build(head) + full)
        let p = try #require(EmbeddedPreviews.find(in: source))
        #expect([p.width, p.height] == [6000, 4000])
        #expect(EmbeddedPreviews.tiffOrientation(Array(p.jpeg(from: source)[12...])) == 8)
    }

    @Test func findsJpegsByScanningWhenTheStructureIsUnknown() {
        let a = T.jpeg(100, 100, extra: [0xff, 0xe1, 0x00, 0x12, 0, 0] + Array(T.jpeg(10, 10)[0..<14]))
        let b = T.jpeg(400, 300, sof: 0xc2)
        let lossless = T.jpeg(50, 50, sof: 0xc3)
        let file: [UInt8] = [1, 2, 3] + a + [9, 9] + lossless + b + [7]
        #expect(
            EmbeddedPreviews.scanForJpegs(file) == [
                .init(offset: 3, length: a.count), .init(offset: 3 + a.count + 2 + lossless.count, length: b.count),
            ])
    }

    @Test func nilWhenThereIsNoPreview() {
        #expect(EmbeddedPreviews.find(in: BytesSource([UInt8](repeating: 0, count: 1000))) == nil)
        #expect(EmbeddedPreviews.find(in: BytesSource([])) == nil)
    }
}
