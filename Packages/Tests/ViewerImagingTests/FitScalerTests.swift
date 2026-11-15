import CoreGraphics
import Foundation
import RawBoyBrowseKit
import Testing
import ViewerImaging

struct FitScalerTests {
    /// A [width] × [height] image: left half [left] grey, right half [right] grey.
    private func halves(width: Int, height: Int, left: UInt8, right: UInt8) throws -> LoadedImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: ImageLoader.displayBitmapInfo.rawValue))
        context.setFillColor(gray: CGFloat(left) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(gray: CGFloat(right) / 255, alpha: 1)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        let image = try #require(context.makeImage())
        return LoadedImage(
            cgImage: image, fullSize: .init(width: Double(width), height: Double(height)), isFullResolution: true)
    }

    private func red(of image: CGImage, x: Int, y: Int) throws -> Int {
        let data = try #require(image.dataProvider?.data)
        let bytes = CFDataGetBytePtr(data)!
        // BGRA: byte 2 is red.
        return Int(bytes[y * image.bytesPerRow + x * 4 + 2])
    }

    @Test func givesTheExactSizeAsked() throws {
        let source = try halves(width: 600, height: 400, left: 40, right: 200)
        let out = try #require(FitScaler.scale(source, width: 301, height: 199))
        #expect(out.cgImage.width == 301)
        #expect(out.cgImage.height == 199)
    }

    @Test func keepsFlatAreasFlat() throws {
        let source = try halves(width: 600, height: 400, left: 40, right: 200)
        let out = try #require(FitScaler.scale(source, width: 300, height: 200, sharpness: 0)).cgImage
        // Well away from the edge in the middle, and at the borders (no dark fringe from the filter's reach).
        for (x, expected) in [(20, 40), (130, 40), (170, 200), (280, 200), (0, 40), (299, 200)] {
            let value = try red(of: out, x: x, y: 100)
            #expect(abs(value - expected) <= 3, "x \(x): \(value), expected \(expected)")
        }
        #expect(abs(try red(of: out, x: 75, y: 0) - 40) <= 3)
        #expect(abs(try red(of: out, x: 75, y: 199) - 40) <= 3)
    }

    @Test func aRegionTakesOnlyThatPart() throws {
        let source = try halves(width: 600, height: 400, left: 40, right: 200)
        // The right half only.
        let right = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        let out = try #require(
            FitScaler.scale(source, region: right, width: 150, height: 200, sharpness: 0)
        ).cgImage
        #expect(abs(try red(of: out, x: 0, y: 100) - 200) <= 3)
        #expect(abs(try red(of: out, x: 149, y: 100) - 200) <= 3)
    }

    @Test func refusesAnEmptyRegionOrSize() throws {
        let source = try halves(width: 100, height: 100, left: 0, right: 255)
        #expect(FitScaler.scale(source, width: 0, height: 10) == nil)
        let outside = CGRect(x: 2, y: 2, width: 0.5, height: 0.5)
        #expect(FitScaler.scale(source, region: outside, width: 10, height: 10) == nil)
    }
}
