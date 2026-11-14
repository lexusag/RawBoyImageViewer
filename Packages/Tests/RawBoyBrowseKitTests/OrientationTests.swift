import RawBoyBrowseKit
import Testing

struct OrientationTests {
    @Test func exifRoundTrips() {
        for n in 1...8 { #expect(Orientation(exif: n).exif == n) }
    }

    @Test func fourTurnsAreNone() {
        var o = Orientation.up
        for _ in 0..<4 { o = o.then(.clockwise) }
        #expect(o == .up)
        #expect(Orientation(exif: 6).then(.anticlockwise) == .up)
        #expect(Orientation.up.then(.clockwise).exif == 6)
        #expect(Orientation.up.then(.anticlockwise).exif == 8)
    }

    @Test func inverseUndoes() {
        for n in 1...8 {
            let o = Orientation(exif: n)
            #expect(o.then(o.inverse) == .up)
            #expect(o.inverse.then(o) == .up)
        }
    }

    @Test func turningAMirroredPhoto() {
        // Mirrored, then a quarter turn clockwise: EXIF 7 (transverse).
        #expect(Orientation(exif: 2).then(.clockwise).exif == 7)
    }

    @Test func sidecarOrientation() throws {
        let text = try XmpSidecar.writeOrientation(nil, 6)
        #expect(XmpSidecar.readOrientation(text) == 6)
        #expect(text.contains(#"xmlns:tiff="http://ns.adobe.com/tiff/1.0/""#))
        let both = try XmpSidecar.write(text, Rating(stars: 2))
        #expect(XmpSidecar.readOrientation(both) == 6)
        #expect(XmpSidecar.read(both) == Rating(stars: 2))
        #expect(XmpSidecar.readOrientation(try XmpSidecar.writeOrientation(both, nil)) == nil)
    }
}
