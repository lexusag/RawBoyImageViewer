import Foundation
import Testing
import ViewerFiles

struct FolderScannerTests {
    @Test func listsPhotosOnlySortedNaturally() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("_bin"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["IMG_10.RAF", "IMG_2.RAF", "IMG_2.jpg", "IMG_2.xmp", ".hidden.jpg", "_bin/IMG_3.RAF"] {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data())
        }

        let names = try FolderScanner.photos(in: dir).map(\.url.lastPathComponent)

        #expect(names == ["IMG_2.jpg", "IMG_2.RAF", "IMG_10.RAF"])
    }
}
