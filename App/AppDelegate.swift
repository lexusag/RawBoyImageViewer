import AppKit

/// Opens what Finder hands over ("Open With", dropping on the Dock icon) and paths given on the command line.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `RawBoy Viewer <folder or photo>`: skip AppKit's own -Flag value pairs.
        var args = Array(CommandLine.arguments.dropFirst())
        var paths: [String] = []
        while let arg = args.first {
            args.removeFirst()
            if arg.hasPrefix("-") {
                if !args.isEmpty { args.removeFirst() }
            } else {
                paths.append(arg)
            }
        }
        if let path = paths.first, FileManager.default.fileExists(atPath: path) {
            MainActor.assumeIsolated { AppModel.shared.open(URL(fileURLWithPath: path)) }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        MainActor.assumeIsolated { AppModel.shared.open(url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
