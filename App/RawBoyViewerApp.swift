import SwiftUI
import ViewerImaging
import ViewerUI

@main
struct RawBoyViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// What the screens take from this app, before the first of them (`AppState.model`) is made.
    init() {
        MainActor.assumeIsolated {
            ViewerHost.updater = Updater.shared
            ViewerHost.versionLine = AppVersion.line
            ViewerHost.handOff = DesktopHandOff()
            ViewerHost.realPreview = CoreImageRealPreview()
        }
    }

    var body: some Scene {
        // One browser window (Window, not WindowGroup): opening files from Finder must not spawn new ones.
        Window("RawBoy Viewer", id: "main") {
            BrowserRoot(app: AppState.model)
                .frame(minWidth: 900, minHeight: 560)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
            }
            ViewerCommands(app: AppState.model)
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
            ViewerSettingsRoot(app: AppState.model)
        }
    }
}

/// The app's one model: the shell owns it and hands it to the screens (and to the delegate, for what Finder opens).
@MainActor
enum AppState {
    static let model = AppModel()
}
