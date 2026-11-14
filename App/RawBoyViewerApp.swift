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
                Button("Rotate Left") { AppModel.shared.rotate(clockwise: false) }
                    .keyboardShortcut("[")
                Button("Rotate Right") { AppModel.shared.rotate(clockwise: true) }
                    .keyboardShortcut("]")
                Divider()
                Button("Export…") { AppModel.shared.perform(.export) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Copy to Folder…") { AppModel.shared.perform(.copyTo) }
                Button("Move to Folder…") { AppModel.shared.perform(.moveTo) }
                Menu("Move to Recent Folder") {
                    ForEach(AppModel.shared.recentDestinations, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            let app = AppModel.shared
                            if let folder = app.browser.folder {
                                app.copyOrMove(app.actionTargets, folder, move: true, to: url)
                            }
                        }
                    }
                }
                Button("Compare (C)") { AppModel.shared.openCompare(AppModel.shared.browser.ratingTargets) }
                Button("Slideshow (S)") {
                    let app = AppModel.shared
                    if let first = app.browser.ratingTargets.first ?? app.browser.visible.first?.id {
                        app.openViewer(at: first)
                        app.viewer.startSlideshow()
                    }
                }
                Divider()
                Button("Copy Photo") { AppModel.shared.perform(.clipboard) }
                    .keyboardShortcut("c", modifiers: [.command, .option])
                Button("Share…") { AppModel.shared.perform(.share) }
                Divider()
                Toggle("Go to the Next Photo After Rating", isOn: Bindable(AppModel.shared.culling).autoAdvance)
            }
            CommandGroup(after: .toolbar) {
                Button("Reload Folder") { AppModel.shared.browser.reload() }
                    .keyboardShortcut("r")
            }
        }
    }
}
