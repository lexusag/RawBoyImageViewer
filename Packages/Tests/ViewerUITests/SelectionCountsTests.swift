import Foundation
import Testing

@testable import ViewerUI

@MainActor
@Suite(.serialized)
struct SelectionCountsTests {
    private func makeModel() throws -> (AppModel, () -> Void) {
        let suiteName = "app.rawboy.viewer.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let old = ViewerSettings.store
        ViewerSettings.store = UserDefaultsSettings(defaults: defaults, prefix: "selection.test.")
        let app = AppModel()
        return (
            app,
            {
                ViewerSettings.store = old
                defaults.removePersistentDomain(forName: suiteName)
            }
        )
    }

    private func makeFolder(photos: [(String, Int)], subfolders: [String] = []) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("selection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, byteCount) in photos {
            FileManager.default.createFile(
                atPath: dir.appendingPathComponent(name).path, contents: Data(repeating: 0, count: byteCount))
        }
        for sub in subfolders {
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        return dir
    }

    @Test func sumsSelectedFileSizesAndIgnoresFoldersAndFilteredOutItems() throws {
        let (app, cleanup) = try makeModel()
        defer { cleanup() }
        let dir = try makeFolder(
            photos: [("a.jpg", 1200), ("b.jpg", 3400), ("c.jpg", 5600)], subfolders: ["Album"])
        defer { try? FileManager.default.removeItem(at: dir) }

        app.browser.showFolders = true
        app.browser.sort = .name
        app.browser.load(dir)

        let empty = app.browser.selectionCounts
        #expect(empty.files == 0)
        #expect(empty.folders == 0)
        #expect(empty.bytes == nil)

        let album = dir.appendingPathComponent("Album").standardizedFileURL
        app.browser.click(GridEntry.folderID(album), command: false, shift: false)
        let folderOnly = app.browser.selectionCounts
        #expect(folderOnly.files == 0)
        #expect(folderOnly.folders == 1)
        #expect(folderOnly.bytes == nil)

        app.browser.click("a.jpg", command: true, shift: false)
        app.browser.click("c.jpg", command: true, shift: false)
        let mixed = app.browser.selectionCounts
        #expect(mixed.files == 2)
        #expect(mixed.folders == 1)
        #expect(mixed.bytes == 6800)

        app.browser.filter = "a"
        let filtered = app.browser.selectionCounts
        #expect(filtered.files == 1)
        #expect(filtered.folders == 1)
        #expect(filtered.bytes == 1200)
    }
}
