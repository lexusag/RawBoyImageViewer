import RawBoyBrowseKit
import Testing

struct ExifFormatTests {
    @Test func shutter() {
        #expect(ExifFormat.shutter(1.0 / 240) == "1/240 s")
        #expect(ExifFormat.shutter(0.125) == "1/8 s")
        #expect(ExifFormat.shutter(2) == "2 s")
        #expect(ExifFormat.shutter(1.3) == "1.3 s")
        #expect(ExifFormat.shutter(0.4) == "0.4 s")
        #expect(ExifFormat.shutter(0) == nil)
    }

    @Test func apertureIsoBias() {
        #expect(ExifFormat.aperture(2.8) == "f/2.8")
        #expect(ExifFormat.aperture(11) == "f/11")
        #expect(ExifFormat.iso(100) == "ISO 100")
        #expect(ExifFormat.bias(0) == "0 EV")
        #expect(ExifFormat.bias(1.0 / 3) == "+0.3 EV")
        #expect(ExifFormat.bias(-1.7) == "−1.7 EV")
    }

    @Test func focalLength() {
        #expect(ExifFormat.focalLength(63, equivalent35: 50) == "63 mm (50 mm in 35 mm terms)")
        #expect(ExifFormat.focalLength(50, equivalent35: 50) == "50 mm")
        #expect(ExifFormat.focalLength(nil, equivalent35: 50) == nil)
    }

    @Test func codes() {
        #expect(ExifFormat.program(3) == "Aperture priority")
        #expect(ExifFormat.metering(5) == "Multi-segment")
        #expect(ExifFormat.flash(0x10) == "Off")
        #expect(ExifFormat.flash(0x19) == "Fired (auto)")
        #expect(ExifFormat.flash(0) == "Did not fire")
        #expect(ExifFormat.whiteBalance(0) == "Auto")
    }

    @Test func camera() {
        #expect(ExifFormat.camera(make: "FUJIFILM", model: "GFX 50R") == "FUJIFILM GFX 50R")
        #expect(ExifFormat.camera(make: "Canon", model: "Canon EOS R5") == "Canon EOS R5")
        #expect(ExifFormat.camera(make: "Google", model: "Pixel 9 Pro") == "Google Pixel 9 Pro")
        #expect(ExifFormat.camera(make: "NIKON CORPORATION", model: "NIKON Z 6") == "NIKON Z 6")
        #expect(ExifFormat.camera(make: nil, model: nil) == nil)
    }

    @Test func coordinates() {
        #expect(
            ExifFormat.coordinates(latitude: 50.45012, latitudeRef: "N", longitude: 30.52341, longitudeRef: "E")
                == "50.4501° N, 30.5234° E")
    }
}
