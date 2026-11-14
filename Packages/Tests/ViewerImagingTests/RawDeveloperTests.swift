import Foundation
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
