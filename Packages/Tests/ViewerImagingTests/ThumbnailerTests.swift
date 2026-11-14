import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ViewerImaging

struct ThumbnailerTests {
    @Test func scalesLongEdgeDown() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try writePNG(width: 600, height: 400, to: url)

        let thumb = try #require(Thumbnailer.thumbnail(at: url, maxPixelSize: 150))

        #expect(thumb.width == 150)
        #expect(thumb.height == 100)
    }

    @Test func returnsNilForNonImages() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not an image".utf8).write(to: url)

        #expect(Thumbnailer.thumbnail(at: url, maxPixelSize: 150) == nil)
    }

    private func writePNG(width: Int, height: Int, to url: URL) throws {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let dest = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
    }
}
