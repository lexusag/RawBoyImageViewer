import CoreGraphics
import Foundation
import RawBoyBrowseKit
import Testing
import ViewerImaging

struct RawDeveloperTests {
    @Test func notARaw() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try TestImages.writePNG(width: 60, height: 40, to: url)
        // Core Image's RAW filter would open a PNG too; the developer only takes raws.
        #expect(RawDeveloper.develop(url, maxPixelSize: 40) == nil)
    }

    /// RAWBOY_SAMPLES=<folder with raws>: each develops at screen size (never in CI).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RAWBOY_SAMPLES"] != nil)) func samples() throws {
        let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RAWBOY_SAMPLES"]!)
        let raws = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { ["dng", "raf", "arw", "cr3", "nef"].contains($0.pathExtension.lowercased()) }
        for url in raws {
            let started = Date()
            let image = try #require(RawDeveloper.develop(url, maxPixelSize: 3440))
            print(
                "\(url.lastPathComponent): \(image.cgImage.width)×\(image.cgImage.height) in "
                    + "\(Int(Date().timeIntervalSince(started) * 1000)) ms")
            #expect(max(image.cgImage.width, image.cgImage.height) <= 3440)
        }
    }
}

/// A host's own raw development (RawBoy's engine, say) takes the place of Core Image's.
struct RealPreviewProviderTests {
    final class Recorder: RealPreviewProvider, @unchecked Sendable {
        nonisolated(unsafe) var calls: [(url: URL, size: Int?, orientation: Int?)] = []
        func develop(_ url: URL, maxPixelSize: Int?, orientation: Int?) -> LoadedImage? {
            calls.append((url, maxPixelSize, orientation))
            let context = CGContext(
                data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
            return LoadedImage(
                cgImage: context.makeImage()!, fullSize: Size2D(width: 4, height: 2),
                isFullResolution: maxPixelSize == nil)
        }
    }

    @Test func theStoreAsksTheHostsProviderForDevelopedKinds() async throws {
        let recorder = Recorder()
        let store = ImageStore(previewPixelSize: 300, realPreview: recorder)
        let url = URL(fileURLWithPath: "/nowhere/IMG_1.DNG")
        let small = try #require(await store.image(url, .developed, orientation: 6))
        let full = try #require(await store.image(url, .developedFull))
        #expect(!small.isFullResolution && full.isFullResolution)
        #expect(recorder.calls.map(\.size) == [300, nil])
        #expect(recorder.calls.map(\.orientation) == [6, nil])
        // A second ask is a cache hit: the provider isn't called again.
        _ = await store.image(url, .developed, orientation: 6)
        #expect(recorder.calls.count == 2)
    }
}
