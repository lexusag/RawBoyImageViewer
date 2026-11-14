import AppKit
import RawBoyBrowseKit
import SwiftUI
import ViewerImaging

/// The few choices that are personal. Everything else follows RawBoy and isn't a setting.
enum SettingsKeys {
    static let openLastFolder = "browser.openLastFolder"
    static let wheel = "viewer.wheel"
    static let slideshowSeconds = "viewer.slideshowSeconds"
    static let editorPath = "files.editorPath"

    static var opensLastFolder: Bool { UserDefaults.standard.object(forKey: openLastFolder) as? Bool ?? true }
    /// The mouse wheel zooms instead of changing photos.
    static var wheelZooms: Bool { UserDefaults.standard.string(forKey: wheel) == "zoom" }
    static var slideshow: Double {
        let s = UserDefaults.standard.double(forKey: slideshowSeconds)
        return s >= 1 ? s : 4
    }
}

struct SettingsView: View {
    let app: AppModel
    @AppStorage(SettingsKeys.openLastFolder) private var openLastFolder = true
    @AppStorage(SettingsKeys.wheel) private var wheel = "navigate"
    @AppStorage(SettingsKeys.slideshowSeconds) private var slideshowSeconds = 4.0
    @AppStorage(SettingsKeys.editorPath) private var editorPath = ""
    @AppStorage(CullingStore.Keys.trashNotice) private var trashNoticeShown = false
    @State private var cacheSize: Int64 = 0
    @State private var autoUpdate = Updater.shared.checksAutomatically

    var body: some View {
        Form {
            Section("Browser") {
                Toggle("Open the last folder at launch", isOn: $openLastFolder)
                LabeledContent("Thumbnail cache") {
                    HStack {
                        Text(ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                            .foregroundStyle(Theme.ashMuted)
                        Button("Clear") {
                            DiskThumbnailCache.shared?.clear()
                            cacheSize = DiskThumbnailCache.shared?.size ?? 0
                        }
                    }
                }
            }
            Section("Viewer") {
                Picker("Mouse wheel", selection: $wheel) {
                    Text("Changes photos (zooms once zoomed in)").tag("navigate")
                    Text("Zooms").tag("zoom")
                }
                LabeledContent("Slideshow") {
                    Stepper(
                        "\(Int(slideshowSeconds)) s per photo", value: $slideshowSeconds, in: 2...15, step: 1)
                }
                Toggle("Develop raws (real preview, R)", isOn: Bindable(app.viewer.model).realPreview)
                Toggle("Go to the next photo after rating", isOn: Bindable(app.culling).autoAdvance)
            }
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { _, on in Updater.shared.checksAutomatically = on }
                Button("Check Now") { Updater.shared.checkForUpdates() }
            }
            Section("Files") {
                LabeledContent("External editor (E)") {
                    HStack {
                        Text(editorName).foregroundStyle(Theme.ashMuted)
                        Button("Choose…", action: chooseEditor)
                        if !editorPath.isEmpty { Button("Darktable or default") { editorPath = "" } }
                    }
                }
                Toggle(
                    "Ask before moving to the Trash in a synced folder",
                    isOn: Binding(
                        get: { !trashNoticeShown }, set: { trashNoticeShown = !$0 }))
                LabeledContent("Export folder") {
                    HStack {
                        Text((AppModel.exportFolder.path as NSString).abbreviatingWithTildeInPath)
                            .foregroundStyle(Theme.ashMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.canCreateDirectories = true
                            if panel.runModal() == .OK, let url = panel.url { AppModel.exportFolder = url }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .task { cacheSize = await Task.detached { DiskThumbnailCache.shared?.size ?? 0 }.value }
    }

    private var editorName: String {
        editorPath.isEmpty
            ? app.viewer.model.editor.name : URL(fileURLWithPath: editorPath).deletingPathExtension().lastPathComponent
    }

    private func chooseEditor() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { editorPath = url.path }
    }
}
