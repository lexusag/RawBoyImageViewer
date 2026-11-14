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
        try TestImages.writePNG(width: 600, height: 400, to: url)

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

}

struct ImageLoaderTests {
    @Test func previewOfALargeImageIsScreenSize() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try TestImages.writePNG(width: 4000, height: 3000, to: url)

        let preview = try #require(ImageLoader.preview(of: url, maxPixelSize: 1000))

        #expect(preview.cgImage.width == 1000)
        #expect(preview.fullSize.width == 4000)
        #expect(!preview.isFullResolution)
    }

    @Test func smallImagesLoadInFull() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try TestImages.writePNG(width: 300, height: 200, to: url)

        let preview = try #require(ImageLoader.preview(of: url, maxPixelSize: 1000))

        #expect(preview.cgImage.width == 300)
        #expect(preview.isFullResolution)
    }

    @Test func storeSharesAndCaches() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try TestImages.writePNG(width: 600, height: 400, to: url)
        let store = ImageStore(previewPixelSize: 200)

        async let a = store.image(url, .preview)
        async let b = store.image(url, .preview)
        let (first, second) = await (a, b)

        #expect(first?.cgImage === second?.cgImage)
        #expect(await store.cached(url, .preview)?.cgImage.width == 200)
        #expect(await store.image(url, .full)?.cgImage.width == 600)
    }
}

enum TestImages {
    static func writePNG(width: Int, height: Int, to url: URL) throws {
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

struct DisplayReadyTests {
    @Test func sixteenBitP3BecomesEightBitBGRAInP3() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try #require(
            CGContext(
                data: nil, width: 8, height: 4, bitsPerComponent: 16, bytesPerRow: 0, space: p3,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue))
        let image = try #require(context.makeImage())

        let ready = ImageLoader.displayReady(image)

        #expect(ready.bitsPerComponent == 8)
        #expect(ready.bitmapInfo == ImageLoader.displayBitmapInfo)
        #expect(ready.colorSpace?.name == CGColorSpace.displayP3)
        #expect(ready.width == 8)
        #expect(ImageLoader.displayReady(ready) === ready)
    }
}

struct ThumbnailStoreTests {
    @Test func thumbnailsAreSmallAndCached() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try TestImages.writePNG(width: 2000, height: 1000, to: url)
        let store = ThumbnailStore(pixelSize: 320)

        let first = try #require(await store.thumbnail(url))
        let second = try #require(await store.thumbnail(url))

        #expect(first.cgImage.width == 320)
        #expect(first.cgImage === second.cgImage)
    }
}
