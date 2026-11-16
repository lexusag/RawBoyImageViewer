import AppKit
import RawBoyBrowseKit
import ViewerUI

/// RawBoy Viewer's hand-off to RawBoy's apps: Open With, and RawBoy Desktop's `rawboy-desktop://auto` link.
@MainActor
struct DesktopHandOff: PhotoHandOff {
    /// Bundle ids tried in order: RawBoy Desktop, then darktable.
    static let editorBundleIds = ["app.rawboy.desktop", "org.darktable.darktable", "org.darktable"]

    /// RawBoy Desktop, when installed.
    private var rawBoyDesktop: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "app.rawboy.desktop")
    }

    var editor: (name: String, url: URL?) {
        for id in Self.editorBundleIds {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return (url.deletingPathExtension().lastPathComponent, url)
            }
        }
        return ("default app", nil)
    }

    var canSendToAuto: Bool { rawBoyDesktop != nil }

    /// Hands [urls] (photos and folders) to RawBoy Desktop's Auto batch as [how], through its `rawboy-desktop://auto`
    /// link (it starts the app if needed). A build without the link is started with `--auto` (and `--import-as`), or,
    /// when running, asked to open them: several files or a folder go into Auto with its own New photos choice.
    func sendToAuto(_ urls: [URL], as how: AutoImport) async throws {
        guard let app = rawBoyDesktop else { throw CocoaError(.fileNoSuchFile) }
        // The async variant, not a completion handler: LaunchServices calls handlers on its own queue, where Swift's
        // isolation check traps in a @MainActor type (macOS 27).
        let configuration = NSWorkspace.OpenConfiguration()
        if handlesAutoLink(app), let link = how.link(urls.map(\.path)) {
            _ = try await NSWorkspace.shared.open([link], withApplicationAt: app, configuration: configuration)
            return
        }
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: "app.rawboy.desktop").isEmpty
        if running {
            _ = try await NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: configuration)
        } else {
            configuration.arguments = ["--auto"] + urls.map(\.path) + ["--import-as", how.rawValue]
            _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        }
    }

    /// Whether [app] declares the `rawboy-desktop` URL scheme (older builds don't).
    private func handlesAutoLink(_ app: URL) -> Bool {
        let types = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains("rawboy-desktop") == true }
    }
}
