import AppKit
import ViewerUI

/// Opens what Finder hands over ("Open With", dropping on the Dock icon) and paths given on the command line.
///
/// At launch, opening waits until the browser window is up: SwiftUI shows it after `applicationDidFinishLaunching`,
/// and a viewer opened before then loses the key window to it, which brings back the menu bar and Dock.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var ready = false
    private var keyMonitor: Any?
    private var pending: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = MainActor.assumeIsolated { Updater.shared }
        // The browser's rating keys, by physical key (SwiftUI's key presses are characters, Cyrillic on a Ukrainian
        // layout).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                // ? (Shift + the / key) anywhere but a text field: the keys.
                if event.keyCode == 44, event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                    event.modifierFlags.contains(.shift), !(NSApp.keyWindow?.firstResponder is NSTextView)
                {
                    HelpWindow.toggle()
                    return true
                }
                return AppState.model.browserKey(event)
            } ? nil : event
        }
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
                AppState.model.open(url)
            } else {
                // Back where the last session left off, as RawBoy Browser does.
                AppState.model.openLastFolderIfWanted()
            }
            pending = []
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if ready {
            MainActor.assumeIsolated { AppState.model.open(url) }
        } else {
            pending = [url]
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Ratings still waiting to be written go to disk first. Synchronously: while termination waits
    /// (`.terminateLater`) AppKit runs its own event loop, where main-actor tasks never run, and quitting hung.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { AppState.model.writePendingNow() }
        return .terminateNow
    }

    /// Until a visible non-viewer window is key (at most a second).
    @MainActor
    private func waitForBrowserWindow() async {
        for _ in 0..<50 {
            if let key = NSApp.keyWindow, !AppModel.isViewerWindow(key), key.isVisible { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
