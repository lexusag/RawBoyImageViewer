import RawBoyBrowseKit
import Testing

struct HistogramTests {
    /// Four RGBX pixels: white (clipped), black (crushed), mid grey, pure red (a channel at 255: clipped).
    let pixels: [UInt8] = [255, 255, 255, 0, 0, 1, 0, 0, 128, 128, 128, 0, 255, 0, 0, 0]

    @Test func binsAndClipping() {
        let h = pixels.withUnsafeBytes { Histogram(pixels: $0, width: 4, height: 1, bytesPerRow: 16) }
        #expect(h.red[63] == 2)
        #expect(h.red[32] == 1)
        #expect(h.red[0] == 1)
        #expect(h.highlights == 0.5)
        #expect(h.shadows == 0.25)
        #expect(h.peak == 1)
    }

    @Test func bgraOffsets() {
        // The same red pixel stored BGRA.
        let bgra: [UInt8] = [0, 0, 255, 255]
        let h = bgra.withUnsafeBytes {
            Histogram(pixels: $0, width: 1, height: 1, bytesPerRow: 4, redOffset: 2, greenOffset: 1, blueOffset: 0)
        }
        #expect(h.red[63] == 1)
        #expect(h.blue[0] == 1)
    }

    @Test func overlayPaintsOnlyClippedPixels() {
        var out = [UInt8](repeating: 9, count: 16)
        let any = pixels.withUnsafeBytes { src in
            out.withUnsafeMutableBytes { dst in
                ClipWarning.overlay(pixels: src, into: dst, width: 4, height: 1, bytesPerRow: 16)
            }
        }
        #expect(any)
        #expect(Array(out[0..<4]) == [0, 0, 255, 255])  // red, BGRA
        #expect(Array(out[4..<8]) == [255, 89, 0, 255])  // blue
        #expect(Array(out[8..<12]) == [0, 0, 0, 0])
    }

    @Test func percentages() {
        #expect(Histogram.percent(0.123) == "12%")
        #expect(Histogram.percent(0.004) == "0.4%")
        #expect(Histogram.percent(0.0004) == "<0.1%")
    }
}
