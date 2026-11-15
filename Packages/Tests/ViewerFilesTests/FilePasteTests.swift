import Foundation
import Testing
import ViewerFiles

struct FilePasteTests {
    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func touch(_ names: [String], in dir: URL) {
        for name in names {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data([1]))
        }
    }

    @Test func pastesIntoAnotherFolderUnderTheSameNames() throws {
        let a = try makeDir()
        let b = try makeDir()
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
        }
        touch(["IMG_1.CR2", "IMG_1.jpg", "IMG_1.xmp"], in: a)

        let sources = ["IMG_1.CR2", "IMG_1.jpg", "IMG_1.xmp"].map { a.appendingPathComponent($0) }
        let result = FilePaste.paste(sources, into: b)

        #expect(result.files == 1 && result.failed == 0)
        let names = try FileManager.default.contentsOfDirectory(atPath: b.path).sorted()
        #expect(names == ["IMG_1.CR2", "IMG_1.jpg", "IMG_1.xmp"])
    }

    @Test func aTakenNameGivesTheWholePhotoOneSuffixAndNeverOverwrites() throws {
        let a = try makeDir()
        defer { try? FileManager.default.removeItem(at: a) }
        touch(["IMG_1.CR2", "IMG_1.CR2.xmp", "IMG_1 2.CR2"], in: a)
        let sources = ["IMG_1.CR2", "IMG_1.CR2.xmp"].map { a.appendingPathComponent($0) }

        FilePaste.paste(sources, into: a)
        FilePaste.paste(sources, into: a)

        let names = try FileManager.default.contentsOfDirectory(atPath: a.path).sorted()
        #expect(
            names == [
                "IMG_1 2.CR2", "IMG_1 3.CR2", "IMG_1 3.CR2.xmp", "IMG_1 4.CR2", "IMG_1 4.CR2.xmp", "IMG_1.CR2",
                "IMG_1.CR2.xmp",
            ])
    }

    @Test func foldersGetANumberAndNeverGoIntoThemselves() throws {
        let a = try makeDir()
        defer { try? FileManager.default.removeItem(at: a) }
        let folder = a.appendingPathComponent("Trip")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        touch(["x.jpg"], in: folder)

        let result = FilePaste.paste([folder], into: a)
        #expect(result.folders == 1)
        #expect(FileManager.default.fileExists(atPath: a.appendingPathComponent("Trip 2/x.jpg").path))

        let inside = FilePaste.paste([folder], into: folder)
        #expect(inside.folders == 0 && inside.failed == 1)
    }
}
