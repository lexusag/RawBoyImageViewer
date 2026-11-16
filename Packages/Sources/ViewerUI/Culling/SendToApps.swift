import AppKit
import RawBoyBrowseKit
import ViewerFiles

/// The apps photos and folders can be sent to ("Send to ▸"): Reblum when it is installed, plus any app added in
/// Settings. Sending opens the files in the app, as Finder's Open With does.
@MainActor
enum SendToApps {
    static let key = "files.sendToApps"

    /// Installed apps named Reblum are offered first, until the list has been edited.
    static var apps: [URL] {
        if let paths = ViewerSettings.store.stringArray(forKey: key) {
            return paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
        }
        return detectedReblum.map { [$0] } ?? []
    }

    static func set(_ urls: [URL]) {
        ViewerSettings.store.set(urls.map(\.path), forKey: key)
    }

    static func add(_ url: URL) {
        let list = apps
        if !list.contains(url) { set(list + [url]) }
    }

    static func remove(_ url: URL) { set(apps.filter { $0 != url }) }

    static func name(of app: URL) -> String { app.deletingPathExtension().lastPathComponent }

    private static var detectedReblum: URL? {
        let folders = ["/Applications", NSHomeDirectory() + "/Applications"]
        return folders.lazy
            .map { URL(fileURLWithPath: $0).appendingPathComponent("Reblum.app") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// [urls] with each folder replaced by the photo files directly inside it (one level, no subfolders). Apps such
    /// as Reblum open files only and fail on a folder ("mmap() failed, errno = 22").
    static func expandingFolders(_ urls: [URL]) -> [URL] {
        urls.flatMap { url -> [URL] in
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue else {
                return [url]
            }
            return ((try? FolderScanner.photos(in: url)) ?? []).map(\.url)
        }
    }

    /// Opens [urls] (photos, or the photos in a folder) in [app].
    static func send(_ urls: [URL], to app: URL, completion: @escaping @MainActor (Error?) -> Void) {
        // The async variant, not a completion handler: this type is @MainActor, so a closure written here is too, and
        // LaunchServices calls handlers on its own queue, where Swift's isolation check traps (macOS 27).
        let files = expandingFolders(urls)
        Task { @MainActor in
            guard !files.isEmpty else { return completion(CocoaError(.fileNoSuchFile)) }
            do {
                let configuration = NSWorkspace.OpenConfiguration()
                _ = try await NSWorkspace.shared.open(files, withApplicationAt: app, configuration: configuration)
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    /// RawBoy Desktop, when installed.
    static var rawBoyDesktop: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "app.rawboy.desktop")
    }

    /// The last Looks / Film / As is choice for RawBoy Auto, offered first next time.
    static var lastAutoImport: AutoImport {
        get { ViewerSettings.store.string(forKey: "files.autoImport").flatMap(AutoImport.init(rawValue:)) ?? .looks }
        set { ViewerSettings.store.set(newValue.rawValue, forKey: "files.autoImport") }
    }

    /// Hands [urls] (photos and folders) to RawBoy Desktop's Auto batch as [how], through its `rawboy-desktop://auto`
    /// link (it starts the app if needed). A build without the link is started with `--auto` (and `--import-as`), or,
    /// when running, asked to open them: several files or a folder go into Auto with its own New photos choice.
    static func sendToAuto(_ urls: [URL], as how: AutoImport, app: URL) async throws {
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
    private static func handlesAutoLink(_ app: URL) -> Bool {
        let types = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return types.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains("rawboy-desktop") == true }
    }

    static func chooseApp() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
