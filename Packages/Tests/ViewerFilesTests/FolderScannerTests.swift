import Foundation
import RawBoyBrowseKit
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

struct CullingFilesTests {
    func folder(_ names: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in names {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data(name.utf8))
        }
        return dir
    }

    @Test func binMovesThePhotoWithItsFilesAndBack() throws {
        let dir = try folder(["IMG_1.RAF", "IMG_1.JPG", "IMG_1.xmp"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let group = PhotoGroup(stem: "IMG_1", main: "IMG_1.RAF", companions: ["IMG_1.JPG"], sidecars: ["IMG_1.xmp"])

        let moves = try FileMoves.moveToBin(group, in: dir)
        #expect(moves.count == 3)
        #expect(FileMoves.binPhotoCount(of: dir) == 2)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("IMG_1.RAF").path))

        // A second photo of the same name gets one suffix for all its files.
        _ = try folder([])
        for name in ["IMG_1.RAF", "IMG_1.xmp"] {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data())
        }
        let second = try FileMoves.moveToBin(
            PhotoGroup(stem: "IMG_1", main: "IMG_1.RAF", companions: [], sidecars: ["IMG_1.xmp"]), in: dir)
        #expect(second.map(\.to.lastPathComponent) == ["IMG_1-1.RAF", "IMG_1-1.xmp"])

        #expect(FileMoves.moveBack(moves) == 0)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("IMG_1.RAF").path))
    }

    @Test func ratingsGoIntoEverySidecarAndReadBack() throws {
        let dir = try folder(["IMG_1.RAF"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let group = PhotoGroup(stem: "IMG_1", main: "IMG_1.RAF", companions: [], sidecars: [])

        // Unrated and no sidecar: nothing is created.
        #expect(try SidecarFiles.write(.none, names: ["IMG_1.xmp"], in: dir).isEmpty)
        #expect(try SidecarFiles.write(Rating(stars: 4), names: ["IMG_1.xmp"], in: dir) == ["IMG_1.xmp"])
        let withSidecar = PhotoGroup(stem: "IMG_1", main: "IMG_1.RAF", companions: [], sidecars: ["IMG_1.xmp"])
        #expect(SidecarFiles.rating(of: withSidecar, in: dir) == Rating(stars: 4))
        #expect(SidecarFiles.rating(of: group, in: dir) == .none)
    }
}

@MainActor
struct FolderWatcherTests {
    @Test func reportsNewAndChangedFilesOfTheFolderOnly() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        FileManager.default.createFile(atPath: dir.appendingPathComponent("IMG_1.xmp").path, contents: Data("a".utf8))
        var changes: [FolderWatcher.Change] = []
        let watcher = try #require(FolderWatcher(folder: dir, latency: 0.1) { changes.append($0) })
        try await Task.sleep(for: .milliseconds(300))

        FileManager.default.createFile(atPath: dir.appendingPathComponent("IMG_2.RAF").path, contents: Data())
        FileManager.default.createFile(atPath: dir.appendingPathComponent(".hidden").path, contents: Data())
        FileManager.default.createFile(atPath: dir.appendingPathComponent("sub/IMG_3.RAF").path, contents: Data())
        try Data("b".utf8).write(to: dir.appendingPathComponent("IMG_1.xmp"))
        for _ in 0..<40 where !changes.contains(where: { $0.structural.contains("IMG_2.RAF") }) {
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(300))

        let all = changes.reduce(into: Set<String>()) { $0.formUnion($1.structural.union($1.modified)) }
        #expect(all.contains("IMG_2.RAF"))
        #expect(all.contains("IMG_1.xmp"))
        #expect(!all.contains(".hidden"))
        #expect(!all.contains("IMG_3.RAF"))
        _ = watcher
    }
}
