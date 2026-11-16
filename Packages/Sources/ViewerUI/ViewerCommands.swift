import SwiftUI

/// The File, Edit, Photo and View menu items of the browser and viewer. The host adds its own (About, updates) around them.
public struct ViewerCommands: Commands {
    let app: AppModel

    public init(app: AppModel) { self.app = app }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open…") { app.openFolderPanel() }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { app.undo() }
                .keyboardShortcut("z")
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Move to Trash") { app.moveToTrash() }
                .keyboardShortcut(.delete, modifiers: .command)
        }
        CommandMenu("Photo") {
            Button("Rotate Left") { app.rotate(clockwise: false) }
                .keyboardShortcut("[")
            Button("Rotate Right") { app.rotate(clockwise: true) }
                .keyboardShortcut("]")
            Button("Crop… (K, in the viewer)") { app.viewer.handle(.crop) }
                .disabled(!app.viewer.isOpen)
            Divider()
            Button("Rename… (F2)") { app.rename() }
                .disabled(app.browser.folder == nil)
            Button("Export…") { app.perform(.export) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Copy to Folder…") { app.perform(.copyTo) }
            Button("Move to Folder…") { app.perform(.moveTo) }
            Menu("Move to Recent Folder") {
                ForEach(app.recentDestinations, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        if let folder = app.browser.folder {
                            app.copyOrMove(app.actionTargets, folder, move: true, to: url)
                        }
                    }
                }
            }
            Button("Compare (C)") { app.openCompare(app.browser.ratingTargets) }
            Button("Slideshow (S)") {
                if let first = app.browser.ratingTargets.first ?? app.browser.visible.first?.id {
                    app.openViewer(at: first)
                    app.viewer.startSlideshow()
                }
            }
            Divider()
            Button("Copy Photo") { app.perform(.clipboard) }
                .keyboardShortcut("c", modifiers: [.command, .option])
            Button("Share…") { app.perform(.share) }
            SendToMenu(app: app)
            Button("Send to RawBoy Auto…") { app.perform(.sendToAuto(nil)) }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(!ViewerHost.handOff.canSendToAuto)
            Divider()
            Toggle("Go to the Next Photo After Rating", isOn: Bindable(app.culling).autoAdvance)
        }
        CommandGroup(after: .toolbar) {
            Button("Reload Folder") { app.browser.reload() }
                .keyboardShortcut("r")
        }
    }
}

/// The browser at the chosen interface size (Settings): laid out in a smaller or larger space, then scaled to fit.
public struct BrowserRoot: View {
    let app: AppModel
    @AppStorage(ViewerSettings.key(SettingsKeys.uiScale)) private var uiScale = 1.0

    public init(app: AppModel) { self.app = app }

    public var body: some View {
        let scale = min(max(uiScale, 0.5), 2)
        GeometryReader { geo in
            BrowserView(app: app)
                .frame(width: geo.size.width / scale, height: geo.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .background(
            WindowReader { window in
                app.viewAppeared(browserIn: window)
            } onDisappear: {
                app.viewDisappeared()
            })
    }
}

/// Tells its closure which window the view is in (and when it leaves).
struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void
    var onDisappear: () -> Void = {}

    func makeNSView(context: Context) -> NSView {
        let view = ReaderView()
        view.onWindow = onWindow
        view.onDisappear = onDisappear
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class ReaderView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        var onDisappear: (() -> Void)?
        private var reported = false

        override func viewDidMoveToWindow() {
            if let window, !reported {
                reported = true
                onWindow?(window)
            } else if window == nil, reported {
                reported = false
                onDisappear?()
            }
        }
    }
}

/// The Settings window's content.
public struct ViewerSettingsRoot: View {
    let app: AppModel

    public init(app: AppModel) { self.app = app }

    public var body: some View {
        SettingsView(app: app)
            .preferredColorScheme(.dark)
    }
}
