import AppKit
import CoreGraphics
import Foundation
import ImageIO
import RawBoyBrowseKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
import ViewerImaging

@testable import ViewerUI

/// The host's choices: a settings prefix, its own hand-off, and the viewer in its window. They are process-wide
/// (`ViewerSettings.store`, `ViewerHost`), so these run one at a time.
@MainActor
@Suite(.serialized)
struct HostTests {
    final class Memory: ViewerSettingsStore, @unchecked Sendable {
        nonisolated(unsafe) var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func string(forKey key: String) -> String? { values[key] as? String }
        func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
        func data(forKey key: String) -> Data? { values[key] as? Data }
        func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
        func double(forKey key: String) -> Double { values[key] as? Double ?? 0 }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    struct RecordingHandOff: PhotoHandOff {
        let sent: Memory
        var editor: (name: String, url: URL?) { ("Pro", URL(fileURLWithPath: "/Apps/Pro.app")) }
        var canSendToAuto: Bool { true }
        func openInEditor(_ url: URL) async -> Bool {
            sent.values["editor"] = url.lastPathComponent
            return true
        }
        func sendToAuto(_ urls: [URL], as how: AutoImport) async throws {
            sent.values["urls"] = urls.map(\.lastPathComponent)
            sent.values["how"] = how.rawValue
        }
    }

    private func withStore<T>(_ store: any ViewerSettingsStore, _ body: () throws -> T) rethrows -> T {
        let old = ViewerSettings.store
        ViewerSettings.store = store
        defer { ViewerSettings.store = old }
        return try body()
    }

    @Test func aPrefixedStoreKeepsTheBrowsersChoicesUnderThePrefix() throws {
        let suiteName = "app.rawboy.viewer.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsSettings(defaults: defaults, prefix: "desktop.viewer.")
        withStore(store) {
            let app = AppModel()
            app.browser.thumbnailSize = 222
            app.browser.showFolders = true
            app.culling.autoAdvance = false
        }
        #expect(defaults.object(forKey: "desktop.viewer.browser.thumbnailSize") as? Double == 222)
        #expect(defaults.bool(forKey: "desktop.viewer.browser.showFolders"))
        #expect(defaults.object(forKey: "desktop.viewer.files.autoAdvance") == nil)
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("browser.") }.isEmpty)
        // A model made later reads them back.
        withStore(store) {
            #expect(AppModel().browser.thumbnailSize == 222)
        }
    }

    @Test func viewsReadAndWriteTheStoreNotUserDefaults() {
        let memory = Memory()
        withStore(memory) {
            let scale = ViewerSetting<Double>(wrappedValue: 1, "app.uiScale")
            #expect(scale.wrappedValue == 1)
            scale.wrappedValue = 1.5
            #expect(memory.values["app.uiScale"] as? Double == 1.5)
            #expect(scale.wrappedValue == 1.5)
            let flag = ViewerSetting<Bool>(wrappedValue: true, "browser.openLastFolder")
            flag.projectedValue.wrappedValue = false
            #expect(memory.values["browser.openLastFolder"] as? Bool == false)
            #expect(SettingsKeys.interfaceScale == 1.5)
            #expect(!SettingsKeys.opensLastFolder)
        }
    }

    @Test func aHostsHandOffChoosesTheEditorAndTakesAuto() async throws {
        let sent = Memory()
        let old = ViewerHost.handOff
        ViewerHost.handOff = RecordingHandOff(sent: sent)
        defer { ViewerHost.handOff = old }
        try withStore(Memory()) {
            let model = ViewerModel(culling: CullingStore())
            #expect(model.editor.name == "Pro")
            #expect(model.editor.url?.lastPathComponent == "Pro.app")
        }
        let app = withStore(Memory()) { AppModel() }
        app.sendToAuto([URL(fileURLWithPath: "/p/a.DNG")], as: .film)
        try await Task.sleep(for: .milliseconds(300))
        #expect(sent.values["urls"] as? [String] == ["a.DNG"])
        #expect(sent.values["how"] as? String == AutoImport.film.rawValue)
    }

    @Test func theEditorKeyOpensThePhotoInTheHostsOwnEditor() async throws {
        let sent = Memory()
        let old = ViewerHost.handOff
        ViewerHost.handOff = RecordingHandOff(sent: sent)
        defer { ViewerHost.handOff = old }
        _ = NSApplication.shared
        var options = ViewerOptions()
        options.viewerInHostWindow = true
        let app = withStore(Memory()) { AppModel(options: options) }
        let dir = try photoFolder(["a.jpg"])
        defer { try? FileManager.default.removeItem(at: dir) }
        app.viewer.show(
            folder: dir, groups: [PhotoGroup(stem: "a", main: "a.jpg", companions: [], sidecars: [])], at: 0)
        app.viewer.handle(.openInEditor)
        try await Task.sleep(for: .milliseconds(300))
        #expect(sent.values["editor"] as? String == "a.jpg")
        app.viewer.close()
    }

    private func photoFolder(_ names: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("viewerui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let context = try #require(
            CGContext(
                data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        for name in names {
            let dest = try #require(
                CGImageDestinationCreateWithURL(
                    dir.appendingPathComponent(name) as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(dest, image, nil)
            #expect(CGImageDestinationFinalize(dest))
        }
        return dir
    }

    @Test func theViewerCanLiveInTheHostsWindowWithoutHidingTheDock() async throws {
        _ = NSApplication.shared
        var options = ViewerOptions()
        options.viewerInHostWindow = true
        options.hidesDockAndMenuBar = false
        let app = withStore(Memory()) { AppModel(options: options) }
        let host = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered,
            defer: false)
        host.contentView = NSHostingView(rootView: ViewerView(app: app))
        let dir = try photoFolder(["a.jpg", "b.jpg"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let before = NSApp.presentationOptions

        app.viewer.show(
            folder: dir,
            groups: ["a", "b"].map { PhotoGroup(stem: $0, main: "\($0).jpg", companions: [], sidecars: []) }, at: 0)
        #expect(app.viewer.isOpen)
        #expect(app.viewer.model.isPresented)
        #expect(!app.viewer.model.canFillScreen)
        try await Task.sleep(for: .milliseconds(200))
        // The viewer's view is inside the host's window; it made no window of its own.
        let root = try #require(app.viewer.rootView)
        #expect(root.window === host)
        #expect(app.viewer.window === host)
        #expect(NSApp.windows.allSatisfy { !($0 is ViewerWindow) })
        #expect(NSApp.presentationOptions == before)

        var closed: String??
        app.viewer.onClose = { closed = .some($0) }
        app.viewer.close()
        #expect(!app.viewer.isOpen)
        #expect(!app.viewer.model.isPresented)
        #expect(closed == .some("a.jpg"))
        #expect(NSApp.presentationOptions == before)
    }

    private func groups(_ stems: [String]) -> [PhotoGroup] {
        stems.map { PhotoGroup(stem: $0, main: "\($0).jpg", companions: [], sidecars: []) }
    }

    @Test func screenPlacementPicksTheDisplayTheWindowIsOnOrNilWhenItIsGone() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let second = CGRect(x: 1440, y: 0, width: 2560, height: 1440)
        #expect(
            ScreenWatch.screenIndex(for: CGRect(x: 1440, y: 0, width: 2560, height: 1440), among: [main, second]) == 1)
        #expect(
            ScreenWatch.screenIndex(for: CGRect(x: 1300, y: 100, width: 400, height: 300), among: [main, second]) == 1)
        #expect(
            ScreenWatch.screenIndex(for: CGRect(x: 1000, y: 100, width: 600, height: 300), among: [main, second]) == 0)
        // The second display is unplugged: the window overlaps nothing.
        #expect(ScreenWatch.screenIndex(for: CGRect(x: 1440, y: 0, width: 2560, height: 1440), among: [main]) == nil)
    }

    @Test func theHostChoosesPerOpeningBetweenItsWindowAndAWindowOfTheViewersOwn() async throws {
        _ = NSApplication.shared
        var options = ViewerOptions()
        options.viewerInHostWindow = true
        options.hidesDockAndMenuBar = false
        let app = withStore(Memory()) { AppModel(options: options) }
        let dir = try photoFolder(["a.jpg", "b.jpg"])
        defer { try? FileManager.default.removeItem(at: dir) }
        app.browser.load(dir)
        try await Task.sleep(for: .milliseconds(400))
        // The default: in the host's window.
        app.openSelectedInViewer()
        #expect(app.viewer.isOpen && app.viewer.isEmbedded)
        app.viewer.close()
        // One opening of the other kind: a window of its own, and the host's choice is back afterwards.
        app.openSelectedInViewer(inHostWindow: false)
        #expect(app.viewer.isOpen && !app.viewer.isEmbedded)
        #expect(app.viewer.window is ViewerWindow)
        #expect(app.options.viewerInHostWindow)
        // Leaving Browse closes a window of ours, not a view in the host's.
        app.closeOwnWindows()
        #expect(!app.viewer.isOpen)
        app.openSelectedInViewer()
        app.closeOwnWindows()
        #expect(app.viewer.isOpen)
        app.viewer.close()
        // Changed at runtime: the next one is a window of its own.
        app.options.viewerInHostWindow = false
        app.openSelectedInViewer()
        #expect(!app.viewer.isEmbedded)
        app.viewer.close()
    }

    @Test func theMenuBarAndDockComeBackWhenTheScreenFillingViewerCloses() async throws {
        _ = NSApplication.shared
        var options = ViewerOptions()
        options.hidesDockAndMenuBar = true
        let app = withStore(Memory()) { AppModel(options: options) }
        let dir = try photoFolder(["a.jpg"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let before = NSApp.presentationOptions
        app.viewer.show(folder: dir, groups: groups(["a"]), at: 0)
        #expect(app.viewer.window is ViewerWindow)
        app.viewer.close()
        #expect(!app.viewer.isOpen)
        #expect(NSApp.presentationOptions == before)
        // The same with Compare.
        app.compare.show(folder: dir, ids: ["a.jpg", "a.jpg"], order: groups(["a"]))
        #expect(app.compare.isOpen && !app.compare.isEmbedded)
        app.compare.close()
        #expect(NSApp.presentationOptions == before)
    }

    @Test func theEditorKeyFromAWindowOfTheViewersOwnHandsOverAndClosesIt() async throws {
        let sent = Memory()
        let old = ViewerHost.handOff
        ViewerHost.handOff = RecordingHandOff(sent: sent)
        defer { ViewerHost.handOff = old }
        _ = NSApplication.shared
        var options = ViewerOptions()
        options.hidesDockAndMenuBar = false
        let app = withStore(Memory()) { AppModel(options: options) }
        let dir = try photoFolder(["a.jpg"])
        defer { try? FileManager.default.removeItem(at: dir) }
        app.viewer.show(folder: dir, groups: groups(["a"]), at: 0)
        #expect(app.viewer.window is ViewerWindow)
        app.viewer.handle(.openInEditor)
        try await Task.sleep(for: .milliseconds(400))
        #expect(sent.values["editor"] as? String == "a.jpg")
        #expect(!app.viewer.isOpen)
    }

    @Test func compareCanLiveInTheHostsWindowToo() async throws {
        _ = NSApplication.shared
        var options = ViewerOptions()
        options.viewerInHostWindow = true
        options.hidesDockAndMenuBar = false
        let app = withStore(Memory()) { AppModel(options: options) }
        let host = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled], backing: .buffered,
            defer: false)
        host.contentView = NSHostingView(rootView: CompareView(app: app))
        let dir = try photoFolder(["a.jpg", "b.jpg"])
        defer { try? FileManager.default.removeItem(at: dir) }
        app.browser.load(dir)
        try await Task.sleep(for: .milliseconds(400))
        app.openCompare(["a.jpg", "b.jpg"])
        try await Task.sleep(for: .milliseconds(300))
        #expect(app.compareOpen && app.compare.isEmbedded)
        #expect(app.compare.rootView?.window === host)
        #expect(NSApp.windows.allSatisfy { !($0 is ViewerWindow) })
        app.compare.close()
        #expect(!app.compareOpen)
    }
}
