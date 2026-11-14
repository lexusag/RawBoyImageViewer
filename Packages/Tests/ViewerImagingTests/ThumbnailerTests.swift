import CoreGraphics
import Foundation
import ImageIO
import RawBoyBrowseKit
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
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = DiskThumbnailCache(folder: folder)
        let store = ThumbnailStore(pixelSize: 320, disk: disk)

        let first = try #require(await store.thumbnail(url, size: 1, modified: nil))
        let second = try #require(await store.thumbnail(url, size: 1, modified: nil))

        #expect(first.cgImage.width == 320)
        #expect(first.cgImage === second.cgImage)
        // A new store (another launch) finds it on disk.
        try FileManager.default.removeItem(at: url)
        let again = await ThumbnailStore(pixelSize: 320, disk: disk).thumbnail(url, size: 1, modified: nil)
        #expect(again?.cgImage.width == 320)
    }

    @Test func diskCacheTrimsOldestFirst() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let disk = DiskThumbnailCache(folder: folder, limit: 1)
        for name in ["a", "b"] {
            FileManager.default.createFile(
                atPath: folder.appendingPathComponent(name + ".jpg").path, contents: Data([1]))
        }
        disk.trim()
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 1)
    }
}

struct PhotoMetadataTests {
    @Test func readsTheFieldsThePanelShows() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        let context = try #require(
            CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try #require(context.makeImage())
        let dest = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let props: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "FUJIFILM", kCGImagePropertyTIFFModel: "GFX 50R",
                kCGImagePropertyTIFFSoftware: "darktable 5.4.0",
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifExposureTime: 1.0 / 240, kCGImagePropertyExifFNumber: 4.0,
                kCGImagePropertyExifISOSpeedRatings: [100], kCGImagePropertyExifExposureBiasValue: 0,
                kCGImagePropertyExifExposureProgram: 3, kCGImagePropertyExifMeteringMode: 5,
                kCGImagePropertyExifFlash: 16, kCGImagePropertyExifDateTimeOriginal: "2026:03:01 12:23:15",
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 52.52, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 13.405, kCGImagePropertyGPSLongitudeRef: "E",
            ],
        ]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))

        let m = try #require(PhotoMetadata.read(url))

        #expect(m.camera == "FUJIFILM GFX 50R")
        #expect(m.exposureSummary == "1/240 s  ·  f/4  ·  ISO 100")
        #expect(m.bias == "0 EV")
        #expect(m.program == "Aperture priority")
        #expect(m.metering == "Multi-segment")
        #expect(m.flash == "Off")
        #expect(m.software == "darktable 5.4.0")
        #expect(m.coordinates == "52.5200° N, 13.4050° E")
        #expect(m.lens == nil)
        #expect(m.taken != nil)
    }
}

struct ThumbnailFitTests {
    func image(_ w: Int, _ h: Int) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        return try #require(context.makeImage())
    }

    @Test func rejectsSmallOrLetterboxedEmbeddedThumbnails() throws {
        let portrait = (width: 4500.0, height: 6000.0)
        // A camera's 160 × 120 thumbnail of a portrait photo: too small and the wrong shape.
        #expect(!Thumbnailer.fits(try image(160, 120), size: portrait, maxPixelSize: 480))
        // Big enough but landscape (black bars).
        #expect(!Thumbnailer.fits(try image(480, 360), size: portrait, maxPixelSize: 480))
        #expect(Thumbnailer.fits(try image(360, 480), size: portrait, maxPixelSize: 480))
    }
}

struct ImageAnalysisTests {
    /// Left half white, right half mid grey.
    func image() throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: 100, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 10))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 50, height: 10))
        return try #require(context.makeImage())
    }

    @Test func histogramCountsTheClippedHalf() throws {
        let h = try #require(ImageAnalysis.histogram(of: try image()))
        #expect(abs(h.highlights - 0.5) < 0.01)
        #expect(h.shadows == 0)
    }

    @Test func overlayIsRedOverTheClippedHalfOnly() throws {
        let overlay = try #require(ImageAnalysis.clipOverlay(of: try image()))
        let data = try #require(overlay.dataProvider?.data) as Data
        // BGRA: the first pixel (white) is red, the last (grey) transparent.
        #expect(Array(data[0..<4]) == [0, 0, 255, 255])
        let last = (overlay.height - 1) * overlay.bytesPerRow + (overlay.width - 1) * 4
        #expect(data[last + 3] == 0)
    }
}

/// Orienting must agree with ImageIO's own EXIF handling, orientation by orientation.
struct OrientingTests {
    /// 3 × 2 pixels, each a different grey, so every turn and mirror is told apart.
    func source() throws -> CGImage {
        var pixels: [UInt8] = []
        for v in [10, 40, 70, 100, 130, 160] as [UInt8] { pixels += [v, v, v, 255] }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        return try #require(
            CGImage(
                width: 3, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 12,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    /// The grey of each pixel, row by row from the top.
    func greys(_ image: CGImage) throws -> [UInt8] {
        let context = try #require(
            CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data)
        let bytes = UnsafeBufferPointer(
            start: data.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4)
        return stride(from: 0, to: bytes.count, by: 4).map { bytes[$0] }
    }

    @Test(arguments: 1...8) func matchesImageIO(_ exif: Int) throws {
        let image = try source()
        // ImageIO's answer: a PNG tagged with [exif], read back with its transform applied.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let dest = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyOrientation: exif] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let imageIO = try #require(
            CGImageSourceCreateThumbnailAtIndex(
                src, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 3,
                ] as CFDictionary))

        let ours = Orienting.apply(Orientation(exif: exif), to: image)

        #expect(ours.width == imageIO.width)
        #expect(ours.height == imageIO.height)
        #expect(try greys(ours) == greys(imageIO))
    }
}

struct ExporterTests {
    @Test func resizesTurnsAndNeverOverwrites() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appendingPathComponent("IMG_1.png")
        try TestImages.writePNG(width: 600, height: 400, to: photo)
        let out = folder.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let first = try Exporter.export(
            photo, orientation: 6, to: out, options: ExportOptions(longEdge: 300, removeLocation: true))
        let second = try Exporter.export(photo, orientation: nil, to: out, options: ExportOptions(longEdge: nil))

        #expect(first.lastPathComponent == "IMG_1.jpg")
        #expect(second.lastPathComponent == "IMG_1-1.jpg")
        let a = try #require(ImageLoader.fullSize(of: first))
        #expect(a.width == 200 && a.height == 300)
        let b = try #require(ImageLoader.fullSize(of: second))
        #expect(b.width == 600 && b.height == 400)
        #expect(ImageLoader.fileOrientation(of: first) == 1)
    }

    @Test func orientedPreviewSwapsTheSize() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try TestImages.writePNG(width: 600, height: 400, to: url)
        let turned = try #require(ImageLoader.preview(of: url, maxPixelSize: 600, orientation: 6))
        #expect(turned.fullSize.width == 400)
        #expect(turned.cgImage.width == 400)
    }
}
