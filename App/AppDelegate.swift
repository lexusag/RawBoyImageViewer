import AppKit

/// Opens what Finder hands over ("Open With", dropping on the Dock icon) and paths given on the command line.
///
/// At launch, opening waits until the browser window is up: SwiftUI shows it after `applicationDidFinishLaunching`,
/// and a viewer opened before then loses the key window to it, which brings back the menu bar and Dock.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var ready = false
    private var pending: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `RawBoy Viewer <folder or photo>`: skip AppKit's own -Flag value pairs.
        var args = Array(CommandLine.arguments.dropFirst())
        while let arg = args.first {
            args.removeFirst()
            if arg.hasPrefix("-") {
                if !args.isEmpty { args.removeFirst() }
            } else if FileManager.default.fileExists(atPath: arg) {
                pending.append(URL(fileURLWithPath: arg))
            }
        }
        Task { @MainActor in
            await waitForBrowserWindow()
            ready = true
            if let url = pending.first {
                AppModel.shared.open(url)
            } else if AppModel.shared.browser.folder == nil, let last = BrowserModel.lastFolder {
                // Back where the last session left off, as RawBoy Browser does.
                AppModel.shared.browser.load(last)
            }
            pending = []
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if ready {
            MainActor.assumeIsolated { AppModel.shared.open(url) }
        } else {
            pending = [url]
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Until a visible non-viewer window is key (at most a second).
    @MainActor
    private func waitForBrowserWindow() async {
        for _ in 0..<50 {
            if let key = NSApp.keyWindow, !(key is ViewerWindow), key.isVisible { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
