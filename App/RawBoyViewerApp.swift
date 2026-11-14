import SwiftUI

@main
struct RawBoyViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // One start window (Window, not WindowGroup): opening files from Finder must not spawn new ones.
        Window("RawBoy Viewer", id: "main") {
            StartView(model: AppModel.shared)
                .frame(minWidth: 720, minHeight: 480)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { AppModel.shared.openFolderPanel() }
                    .keyboardShortcut("o")
            }
        }
    }
}
