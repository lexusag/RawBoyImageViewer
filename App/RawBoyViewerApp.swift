import SwiftUI

@main
struct RawBoyViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // One browser window (Window, not WindowGroup): opening files from Finder must not spawn new ones.
        Window("RawBoy Viewer", id: "main") {
            BrowserView(app: AppModel.shared)
                .frame(minWidth: 900, minHeight: 560)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { AppModel.shared.openFolderPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { AppModel.shared.undo() }
                    .keyboardShortcut("z")
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Move to Trash") { AppModel.shared.moveToTrash() }
                    .keyboardShortcut(.delete, modifiers: .command)
            }
            CommandMenu("Photo") {
                Toggle("Go to the Next Photo After Rating", isOn: Bindable(AppModel.shared.culling).autoAdvance)
            }
            CommandGroup(after: .toolbar) {
                Button("Reload Folder") { AppModel.shared.browser.reload() }
                    .keyboardShortcut("r")
            }
        }
    }
}
