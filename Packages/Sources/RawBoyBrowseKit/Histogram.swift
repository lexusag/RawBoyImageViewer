/// A photo's red, green and blue levels, with the share of clipped highlights and crushed shadows. A port of RawBoy's
/// `Histogram` (Histogram.kt / .swift / .ts): keep the bins and the clipping rules the same, so both apps warn about
/// the same pixels.
public struct Histogram: Equatable, Sendable {
    public static let bins = 64
    /// Shown as clipped from this share of the photo (0.1%): a few stray pixels aren't worth a warning.
    public static let clipShown = 0.001

    public let red: [Int]
    public let green: [Int]
    public let blue: [Int]
    /// Fraction 0...1 of pixels with a channel at 255.
    public let highlights: Double
    /// Fraction 0...1 of pixels with every channel at 1 or below.
    public let shadows: Double
    /// Largest bin, ignoring the two end bins (a clipped spike there would flatten everything else).
    public let peak: Int

    /// From 8-bit pixels with [bytesPerPixel] bytes each; the offsets say where red, green and blue are in a pixel
    /// (BGRA: 2, 1, 0).
    public init(
        pixels: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int, bytesPerPixel: Int = 4,
        redOffset: Int = 0, greenOffset: Int = 1, blueOffset: Int = 2
    ) {
        var r = [Int](repeating: 0, count: Self.bins)
        var g = r
        var b = r
        var high = 0
        var low = 0
        for y in 0..<height {
            for x in 0..<width {
                let o = y * bytesPerRow + x * bytesPerPixel
                let pr = Int(pixels[o + redOffset])
                let pg = Int(pixels[o + greenOffset])
                let pb = Int(pixels[o + blueOffset])
                r[pr * Self.bins / 256] += 1
                g[pg * Self.bins / 256] += 1
                b[pb * Self.bins / 256] += 1
                switch ClipWarning.classify(pr, pg, pb) {
                case .highlight: high += 1
                case .shadow: low += 1
                case .none: break
                }
            }
        }
        let n = Double(max(1, width * height))
        red = r
        green = g
        blue = b
        highlights = Double(high) / n
        shadows = Double(low) / n
        let inner = { (a: [Int]) in a[1..<(Self.bins - 1)].max() ?? 0 }
        peak = max(1, inner(r), inner(g), inner(b))
    }

    /// "12%", "0.4%", "<0.1%", as RawBoy writes the clipped shares.
    public static func percent(_ f: Double) -> String {
        if f >= 0.1 { return "\(Int((f * 100).rounded()))%" }
        if f > 0 && f < 0.001 { return "<0.1%" }
        let tenths = (f * 1000).rounded() / 10
        return "\(tenths)%"
    }
}

/// RawBoy's clipping warning (its develop shader's `clipWarning`): a pixel with a channel at 255 shows red, one with
/// every channel at 1 or below blue: the pixels the histogram counts.
public enum ClipWarning {
    public enum Pixel: Equatable, Sendable {
        case highlight, shadow, none
    }

    /// The highlight warning colour, 8-bit RGB.
    public static let highlightColour: (UInt8, UInt8, UInt8) = (255, 0, 0)
    /// The shadow warning colour, 8-bit RGB (0, 0.35, 1).
    public static let shadowColour: (UInt8, UInt8, UInt8) = (0, 89, 255)

    public static func classify(_ r: Int, _ g: Int, _ b: Int) -> Pixel {
        let m = max(r, g, b)
        if m >= 255 { return .highlight }
        if m <= 1 { return .shadow }
        return .none
    }

    /// Fills [out] (BGRA, premultiplied, the same size and row length as [pixels]) with the warning colours where
    /// pixels clip and transparency elsewhere. Returns whether any pixel clips.
    @discardableResult
    public static func overlay(
        pixels: UnsafeRawBufferPointer, into out: UnsafeMutableRawBufferPointer, width: Int, height: Int,
        bytesPerRow: Int, bytesPerPixel: Int = 4, redOffset: Int = 0, greenOffset: Int = 1, blueOffset: Int = 2
    ) -> Bool {
        var any = false
        for y in 0..<height {
            for x in 0..<width {
                let o = y * bytesPerRow + x * bytesPerPixel
                let pixel = classify(
                    Int(pixels[o + redOffset]), Int(pixels[o + greenOffset]), Int(pixels[o + blueOffset]))
                let colour: (UInt8, UInt8, UInt8)?
                switch pixel {
                case .highlight: colour = highlightColour
                case .shadow: colour = shadowColour
                case .none: colour = nil
                }
                let w = y * bytesPerRow + x * 4
                if let (r, g, b) = colour {
                    out[w] = b
                    out[w + 1] = g
                    out[w + 2] = r
                    out[w + 3] = 255
                    any = true
                } else {
                    out[w] = 0
                    out[w + 1] = 0
                    out[w + 2] = 0
                    out[w + 3] = 0
                }
            }
        }
        return any
    }
}
