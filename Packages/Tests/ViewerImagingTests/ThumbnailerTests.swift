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

    @Test func shortEdgeShrinksButNeverEnlarges() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appendingPathComponent("IMG_1.png")
        try TestImages.writePNG(width: 3000, height: 2000, to: photo)
        let out = folder.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let free = try Exporter.export(
            photo, orientation: nil, to: out,
            options: ExportOptions(longEdge: nil, shortEdge: ExportOptions.instagramShortEdge))
        let freeSize = try #require(ImageLoader.fullSize(of: free))
        #expect(freeSize.width == 2160 && freeSize.height == 1440)

        let big = try Exporter.export(
            photo, orientation: nil, to: out, options: .instagram())
        let size = try #require(ImageLoader.fullSize(of: big))
        #expect(size.width == 1440 && size.height == 1920)

        let small = folder.appendingPathComponent("SMALL.png")
        try TestImages.writePNG(width: 600, height: 400, to: small)
        let kept = try Exporter.export(small, orientation: nil, to: out, options: .instagram())
        let keptSize = try #require(ImageLoader.fullSize(of: kept))
        #expect(keptSize.width == 300 && keptSize.height == 400)
    }

    @Test func instagramCrops() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appendingPathComponent("IMG_1.png")
        try TestImages.writePNG(width: 4000, height: 3000, to: photo)
        let out = folder.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        for (crop, expected) in [
            (ExportOptions.Crop.threeFour, (1440, 1920)),
            (.fourFive, (1440, 1800)),
            (.square, (1440, 1440)),
            (.landscape, (2750, 1440)),
            (.nineSixteen, (1440, 2560)),
        ] {
            let exported = try Exporter.export(
                photo, orientation: nil, to: out, options: .instagram(from: ExportOptions(crop: crop)))
            let size = try #require(ImageLoader.fullSize(of: exported))
            #expect(Int(size.width) == expected.0 && Int(size.height) == expected.1)
        }

        let sub = Exporter.effectiveCrop(
            CropRect(left: 0.2, top: 0.1, right: 0.8, bottom: 0.9), aspect: .square, width: 1000, height: 1000)
        #expect(abs(sub.left - 0.2) < 1e-9 && abs(sub.right - 0.8) < 1e-9)
        #expect(abs(sub.top - 0.2) < 1e-9 && abs(sub.bottom - 0.8) < 1e-9)
    }

    @Test func instagramCropsAreExactForOddSizesAndTurns() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let out = folder.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for (w, h, turn) in [(4001, 2999, nil), (3001, 4501, nil), (6000, 4000, 6), (5003, 3331, 8)] as [(Int, Int, Int?)]
        {
            let photo = folder.appendingPathComponent("P\(w)x\(h).png")
            try TestImages.writePNG(width: w, height: h, to: photo)
            let exported = try Exporter.export(
                photo, orientation: turn, to: out, options: .instagram(from: ExportOptions(crop: .threeFour)))
            let size = try #require(ImageLoader.fullSize(of: exported))
            #expect(size.width == 1440 && size.height == 1920)
        }
    }

    @Test func exactSizeKeepsTheShortEdge() {
        #expect(Exporter.exactSize(short: 1440, ratio: 3.0 / 4.0) == (1440, 1920))
        #expect(Exporter.exactSize(short: 1440, ratio: 4.0 / 5.0) == (1440, 1800))
        #expect(Exporter.exactSize(short: 1440, ratio: 9.0 / 16.0) == (1440, 2560))
        #expect(Exporter.exactSize(short: 1440, ratio: 1.91) == (2750, 1440))
    }

    @Test func oldOptionsDecodeWithoutShortEdge() throws {
        let json = Data(#"{"longEdge":3000,"format":"jpeg","quality":0.9,"removeLocation":false}"#.utf8)
        let options = try JSONDecoder().decode(ExportOptions.self, from: json)
        #expect(options.shortEdge == nil && options.crop == nil && options.convertToSRGB == false)
        let roundTrip = try JSONDecoder().decode(
            ExportOptions.self, from: JSONEncoder().encode(ExportOptions.instagram()))
        #expect(roundTrip.isInstagram && roundTrip.crop == .threeFour)
    }

    @Test func replacesOnlyWhenAskedAndOnlyOutsideTheSourceFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let out = folder.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appendingPathComponent("IMG_1.png")
        try TestImages.writePNG(width: 600, height: 400, to: photo)

        _ = try Exporter.export(photo, orientation: nil, to: out, options: ExportOptions(longEdge: 300))
        let again = try Exporter.export(
            photo, orientation: nil, to: out, options: ExportOptions(longEdge: nil, replaceExisting: true))
        #expect(again.lastPathComponent == "IMG_1.jpg")
        #expect(try #require(ImageLoader.fullSize(of: again)).width == 600)
        let names = try FileManager.default.contentsOfDirectory(atPath: out.path)
        #expect(names == ["IMG_1.jpg"])

        // In the photo's own folder the option is ignored: the new file gets a number.
        let beside = try Exporter.export(
            photo, orientation: nil, to: folder, options: ExportOptions(replaceExisting: true))
        #expect(beside.lastPathComponent == "IMG_1.jpg")
        let next = try Exporter.export(
            photo, orientation: nil, to: folder, options: ExportOptions(replaceExisting: true))
        #expect(next.lastPathComponent == "IMG_1-1.jpg")
    }

    @Test func oldOptionsDecodeWithoutReplace() throws {
        let json = Data(#"{"longEdge":3000,"format":"jpeg","quality":0.9,"removeLocation":false}"#.utf8)
        let options = try JSONDecoder().decode(ExportOptions.self, from: json)
        #expect(options.replaceExisting == false)
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

struct CropImageTests {
    @Test func cropsFromTheTopLeft() throws {
        // 4 × 2: the top row dark, the bottom row light.
        let pixels: [UInt8] =
            Array(repeating: [20, 20, 20, 255], count: 4).flatMap { $0 }
            + Array(repeating: [220, 220, 220, 255], count: 4).flatMap { $0 }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(
            CGImage(
                width: 4, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let top = Orienting.crop(image, CropRect(left: 0.5, top: 0, right: 1, bottom: 0.5))
        #expect(top.width == 2 && top.height == 1)
        let data = try #require(top.dataProvider?.data) as Data
        #expect(data[0] == 20)
    }

    @Test func exportCropsToTheLongEdgeAsked() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appendingPathComponent("IMG_1.png")
        try TestImages.writePNG(width: 1200, height: 800, to: photo)
        let out = try Exporter.export(
            photo, orientation: nil, crop: CropRect(left: 0, top: 0, right: 0.5, bottom: 1), to: folder,
            options: ExportOptions(longEdge: 800))
        let size = try #require(ImageLoader.fullSize(of: out))
        #expect(size.width == 600 && size.height == 800)
    }
}
