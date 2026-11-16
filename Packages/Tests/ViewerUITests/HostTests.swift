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
}
