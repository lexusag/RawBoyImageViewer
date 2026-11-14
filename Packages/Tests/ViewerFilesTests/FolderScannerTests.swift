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

struct FolderListingTests {
    @Test func sidecarsSubfoldersAndLocalFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        for sub in ["_bin", "b", "A", "Some.app"] {
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        for name in ["IMG_1.RAF", "IMG_1.xmp", "IMG_1.RAF.xmp"] {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data([1, 2]))
        }

        #expect(try FolderScanner.sidecarNames(in: dir).sorted() == ["IMG_1.RAF.xmp", "IMG_1.xmp"])
        #expect(FolderScanner.subfolders(of: dir).map(\.lastPathComponent) == ["A", "b"])
        let photo = try #require(try FolderScanner.photos(in: dir).first)
        #expect(photo.size == 2)
        #expect(!photo.isOnlineOnly)
    }
}
