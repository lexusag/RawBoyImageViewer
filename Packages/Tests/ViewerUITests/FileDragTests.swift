import AppKit
import Foundation
import Testing

@testable import ViewerUI

@MainActor
@Suite(.serialized)
struct FileDragTests {
    private func makeModel() throws -> (AppModel, () -> Void) {
        let suiteName = "app.rawboy.viewer.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let old = ViewerSettings.store
        ViewerSettings.store = UserDefaultsSettings(defaults: defaults, prefix: "drag.test.")
        let app = AppModel()
        return (
            app,
            {
                ViewerSettings.store = old
                defaults.removePersistentDomain(forName: suiteName)
            }
        )
    }

    private func makeFolder(photos: [String], subfolders: [String] = []) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("filedrag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in photos {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data())
        }
        for sub in subfolders {
            try FileManager.default.createDirectory(
                at: dir.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        return dir
    }

    @Test func draggingASelectedItemReturnsEverySelectedFileAndFolder() throws {
        let (app, cleanup) = try makeModel()
        defer { cleanup() }
        let dir = try makeFolder(photos: ["a.jpg", "b.jpg", "c.jpg"], subfolders: ["Album"])
        defer { try? FileManager.default.removeItem(at: dir) }

        app.browser.showFolders = true
        app.browser.sort = .name
        app.browser.load(dir)

        let album = dir.appendingPathComponent("Album").standardizedFileURL
        app.browser.click(GridEntry.folderID(album), command: false, shift: false)
        app.browser.click("a.jpg", command: true, shift: false)
        app.browser.click("c.jpg", command: true, shift: false)

        let leadEntry = try #require(app.browser.items.first { $0.id == "c.jpg" })
        let urls = app.beginDrag(leadEntry)

        #expect(urls.map(\.lastPathComponent) == ["Album", "a.jpg", "c.jpg"])
        #expect(app.drag?.ids == ["a.jpg", "c.jpg"])
        #expect(app.drag?.folders.map(\.lastPathComponent) == ["Album"])
        #expect(app.drag?.lead?.lastPathComponent == "c.jpg")
        #expect(app.isOwnDrag(urls))

        app.endDrag()
        #expect(app.drag == nil)
        #expect(!app.isOwnDrag(urls))
    }

    @Test func draggingAnUnselectedItemSelectsAndDragsOnlyThatItem() throws {
        let (app, cleanup) = try makeModel()
        defer { cleanup() }
        let dir = try makeFolder(photos: ["a.jpg", "b.jpg", "c.jpg"])
        defer { try? FileManager.default.removeItem(at: dir) }

        app.browser.sort = .name
        app.browser.load(dir)
        app.browser.click("a.jpg", command: false, shift: false)
        app.browser.click("b.jpg", command: true, shift: false)

        let cEntry = try #require(app.browser.items.first { $0.id == "c.jpg" })
        let urls = app.beginDrag(cEntry)

        #expect(urls.map(\.lastPathComponent) == ["c.jpg"])
        #expect(app.browser.selection == ["c.jpg"])
        #expect(app.drag?.ids == ["c.jpg"])
    }

    @Test func draggingTheParentTileStartsNothing() throws {
        let (app, cleanup) = try makeModel()
        defer { cleanup() }
        let dir = try makeFolder(photos: ["a.jpg"])
        defer { try? FileManager.default.removeItem(at: dir) }

        app.browser.showFolders = true
        app.browser.load(dir)

        let parent = try #require(app.browser.items.first { $0.isParent })
        #expect(app.beginDrag(parent).isEmpty)
        #expect(app.drag == nil)
    }

    @Test func draggingItemsBuildsOnePasteboardItemPerURL() throws {
        let urls = [
            URL(fileURLWithPath: "/tmp/one.jpg"),
            URL(fileURLWithPath: "/tmp/two.dng"),
            URL(fileURLWithPath: "/tmp/three.heic"),
        ]
        let point = NSPoint(x: 100, y: 80)
        let items = FileDrag.draggingItems(for: urls, around: point)

        #expect(items.count == 3)
        let size = FileDrag.iconSize
        let expectedFrame = NSRect(
            x: point.x - size.width / 2, y: point.y - size.height / 2,
            width: size.width, height: size.height)
        for (item, url) in zip(items, urls) {
            #expect(item.draggingFrame == expectedFrame)
            #expect((item.item as? URL) == url)
            let components = try #require(item.imageComponentsProvider?())
            #expect(components.count == 1)
            #expect(components[0].key == .icon)
        }
    }
}
