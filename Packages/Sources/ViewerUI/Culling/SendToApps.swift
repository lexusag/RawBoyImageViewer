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
        if let paths = ViewerSettings.current.stringArray(forKey: key) {
            return paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
        }
        return detectedReblum.map { [$0] } ?? []
    }

    static func set(_ urls: [URL]) {
        ViewerSettings.current.set(urls.map(\.path), forKey: key)
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

    /// The last Looks / Film / As is choice for RawBoy Auto, offered first next time.
    static var lastAutoImport: AutoImport {
        get { ViewerSettings.current.string(forKey: "files.autoImport").flatMap(AutoImport.init(rawValue:)) ?? .looks }
        set { ViewerSettings.current.set(newValue.rawValue, forKey: "files.autoImport") }
    }

    static func chooseApp() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
