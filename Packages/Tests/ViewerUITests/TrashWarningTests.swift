import AppKit
import Foundation
import RawBoyBrowseKit
import Testing

@testable import ViewerUI

@MainActor
@Suite(.serialized)
struct TrashWarningTests {
    private func makeModel() throws -> (AppModel, () -> Void) {
        _ = NSApplication.shared
        let suiteName = "app.rawboy.viewer.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let old = ViewerSettings.store
        ViewerSettings.store = UserDefaultsSettings(defaults: defaults, prefix: "trash.test.")
        var options = ViewerOptions()
        options.viewerInHostWindow = true
        options.hidesDockAndMenuBar = false
        let app = AppModel(options: options)
        return (
            app,
            {
                ViewerSettings.store = old
                defaults.removePersistentDomain(forName: suiteName)
            }
        )
    }

    private func makeFolder(photos: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trashwarn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in photos {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data())
        }
        return dir
    }

    @Test func viewerMoveToTrashAsksFirstAndCancelsWithoutDeleting() throws {
        let (app, cleanup) = try makeModel()
        defer { cleanup() }
        let dir = try makeFolder(photos: ["a.jpg", "b.jpg"])
        defer { try? FileManager.default.removeItem(at: dir) }

        app.browser.sort = .name
        app.browser.load(dir)
        app.openViewer(at: "a.jpg")
        defer { app.viewer.close() }

        var prompts: [AppModel.TrashPrompt] = []
        app.confirmTrash = { prompt in
            prompts.append(prompt)
            return AppModel.TrashConfirmation(confirmed: false, suppress: false)
        }

        app.viewer.handle(.moveToTrash)

        #expect(prompts.count == 1)
        #expect(prompts[0].messageText == "Move 1 photo to the Trash?")
        #expect(prompts[0].allowsSuppression)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a.jpg").path))
    }

    @Test func compareMoveToTrashAsksFirstAndCancelsWithoutDeleting() throws {
        let (app, cleanup) = try makeModel()
        defer { cleanup() }
        let dir = try makeFolder(photos: ["a.jpg", "b.jpg"])
        defer { try? FileManager.default.removeItem(at: dir) }

        app.browser.sort = .name
        app.browser.load(dir)
        app.openCompare(["a.jpg", "b.jpg"])
        defer { app.compare.close() }

        var prompts: [AppModel.TrashPrompt] = []
        app.confirmTrash = { prompt in
            prompts.append(prompt)
            return AppModel.TrashConfirmation(confirmed: false, suppress: false)
        }

        app.compare.handle(.moveToTrash)

        #expect(prompts.count == 1)
        #expect(prompts[0].messageText == "Move 1 photo to the Trash?")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a.jpg").path))
    }

    @Test func suppressingPhotoWarningSkipsNextPhotoPromptButStillAsksForFolders() async throws {
        let (app, cleanup) = try makeModel()
        defer { cleanup() }
        let dir = try makeFolder(photos: ["a.jpg", "b.jpg"])
        let sub = dir.appendingPathComponent("Sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        app.browser.sort = .name
        app.browser.load(dir)
        app.openViewer(at: "a.jpg")
        defer { app.viewer.close() }

        var prompts: [AppModel.TrashPrompt] = []
        app.confirmTrash = { prompt in
            prompts.append(prompt)
            return AppModel.TrashConfirmation(confirmed: true, suppress: true)
        }

        app.viewer.handle(.moveToTrash)
        try await Task.sleep(for: .milliseconds(100))
        #expect(prompts.count == 1)
        #expect(ViewerSettings.current.bool(forKey: CullingStore.Keys.trashPhotosWithoutAsking))
        _ = app.culling.undo()

        // Next photo trash skips the prompt.
        app.confirmTrash = { prompt in
            prompts.append(prompt)
            return AppModel.TrashConfirmation(confirmed: false, suppress: false)
        }
        app.viewer.handle(.moveToTrash)
        try await Task.sleep(for: .milliseconds(100))
        #expect(prompts.count == 1)
        _ = app.culling.undo()

        // Trashing a folder still asks, and does not allow suppression.
        app.trash(photos: [], folders: [sub])
        #expect(prompts.count == 2)
        #expect(prompts[1].messageText == "Move the folder “Sub” to the Trash?")
        #expect(!prompts[1].allowsSuppression)
    }
}
