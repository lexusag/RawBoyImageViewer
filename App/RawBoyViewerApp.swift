import SwiftUI
import ViewerUI

@main
struct RawBoyViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // One browser window (Window, not WindowGroup): opening files from Finder must not spawn new ones.
        Window("RawBoy Viewer", id: "main") {
            BrowserRoot()
                .frame(minWidth: 900, minHeight: 560)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
            }
            ViewerCommands()
            CommandGroup(replacing: .help) {
                // The version, at the top of the Help menu (the standard About panel stays in the app menu).
                Button("About \(AppVersion.line)") {}
                    .disabled(true)
                Divider()
                Button("RawBoy Viewer Keys") { HelpWindow.toggle() }
                    .keyboardShortcut("/")
            }
        }
        Settings {
            ViewerSettingsRoot()
        }
    }
}
