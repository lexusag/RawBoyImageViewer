import Foundation
import RawBoyBrowseKit
import Testing

/// Real raws, when the folder RAWBOY_SAMPLES names exists (never in CI): every raw has a date; the previews found are
/// printed (phone DNGs have no embedded JPEG, Adobe's JPEG XL DNGs only a 256 px one).
/// `RAWBOY_SAMPLES=~/_claude/photos swift test --filter SampleFiles`
struct SampleFilesTests {
    static let folder = ProcessInfo.processInfo.environment["RAWBOY_SAMPLES"].map { URL(fileURLWithPath: $0) }

    @Test(.enabled(if: folder != nil)) func everyRawHasADate() throws {
        let urls = try FileManager.default.contentsOfDirectory(at: Self.folder!, includingPropertiesForKeys: nil)
            .filter { PhotoFileType(fileName: $0.lastPathComponent) == .raw }
        #expect(!urls.isEmpty)
        for url in urls {
            let source = try #require(FileSource(url: url))
            let started = Date()
            let preview = EmbeddedPreviews.find(in: source)
            let date = CaptureDate.find(in: source)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            print(
                "\(url.lastPathComponent): preview \(preview.map { "\($0.width)×\($0.height) o\($0.rawOrientation)/\($0.jpegOrientation)" } ?? "none"), date \(date ?? "none"), \(ms) ms"
            )
            #expect(date != nil, "\(url.lastPathComponent)")
        }
    }
}
