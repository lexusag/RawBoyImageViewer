import AppKit

/// The apps photos and folders can be sent to ("Send to ▸"): Reblum when it is installed, plus any app added in
/// Settings. Sending opens the files in the app, as Finder's Open With does.
enum SendToApps {
    static let key = "files.sendToApps"

    /// Installed apps named Reblum are offered first, until the list has been edited.
    static var apps: [URL] {
        if let paths = UserDefaults.standard.stringArray(forKey: key) {
            return paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
        }
        return detectedReblum.map { [$0] } ?? []
    }

    static func set(_ urls: [URL]) {
        UserDefaults.standard.set(urls.map(\.path), forKey: key)
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

    /// Opens [urls] (photos or a folder) in [app].
    @MainActor
    static func send(_ urls: [URL], to app: URL, completion: @escaping @MainActor (Error?) -> Void) {
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) {
            _, error in
            Task { @MainActor in completion(error) }
        }
    }

    static func chooseApp() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
