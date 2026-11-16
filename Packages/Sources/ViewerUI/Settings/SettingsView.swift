import AppKit
import RawBoyBrowseKit
import SwiftUI
import ViewerImaging

/// The few choices that are personal. Everything else follows RawBoy and isn't a setting.
enum SettingsKeys {
    static let openLastFolder = "browser.openLastFolder"
    static let folderContents = "browser.folderContents"
    static let wheel = "viewer.wheel"
    static let slideshowSeconds = "viewer.slideshowSeconds"
    static let editorPath = "files.editorPath"
    static let uiScale = "app.uiScale"
    static let uiScales: [Double] = [0.85, 1, 1.15, 1.3, 1.5]

    /// Size of the browser's interface, 1 = as designed.
    static var interfaceScale: Double {
        let s = ViewerSettings.store.double(forKey: uiScale)
        return s >= 0.5 && s <= 2 ? s : 1
    }

    static var opensLastFolder: Bool { ViewerSettings.store.object(forKey: openLastFolder) as? Bool ?? true }
    /// The mouse wheel zooms instead of changing photos.
    static var wheelZooms: Bool { ViewerSettings.store.string(forKey: wheel) == "zoom" }
    static var slideshow: Double {
        let s = ViewerSettings.store.double(forKey: slideshowSeconds)
        return s >= 1 ? s : 4
    }
}

struct SettingsView: View {
    let app: AppModel
    @AppStorage(ViewerSettings.key(SettingsKeys.openLastFolder)) private var openLastFolder = true
    @AppStorage(ViewerSettings.key(SettingsKeys.folderContents)) private var folderContents = false
    @AppStorage(ViewerSettings.key(SettingsKeys.wheel)) private var wheel = "navigate"
    @AppStorage(ViewerSettings.key(SettingsKeys.slideshowSeconds)) private var slideshowSeconds = 4.0
    @AppStorage(ViewerSettings.key(SettingsKeys.uiScale)) private var uiScale = 1.0
    @AppStorage(ViewerSettings.key(SettingsKeys.editorPath)) private var editorPath = ""
    @AppStorage(ViewerSettings.key(CullingStore.Keys.trashNotice)) private var trashNoticeShown = false
    @AppStorage(ViewerSettings.key(CullingStore.Keys.trashPhotosWithoutAsking)) private var trashPhotosWithoutAsking =
        false
    @State private var cacheSize: Int64 = 0
    @State private var sendApps = SendToApps.apps
    @State private var autoUpdate = HostInfo.updater?.checksAutomatically ?? false

    var body: some View {
        Form {
            Section("Browser") {
                Picker("Interface size", selection: $uiScale) {
                    ForEach(SettingsKeys.uiScales, id: \.self) { Text("\(Int(($0 * 100).rounded()))%").tag($0) }
                }
                Toggle("Open the last folder at launch", isOn: $openLastFolder)
                Toggle("Show what is inside folder tiles (needs the Folder button on)", isOn: $folderContents)
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
            if let updater = HostInfo.updater {
                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: $autoUpdate)
                        .onChange(of: autoUpdate) { _, on in updater.checksAutomatically = on }
                    Button("Check Now") { updater.checkForUpdates() }
                }
            }
            Section("Files") {
                LabeledContent("External editor (E)") {
                    HStack {
                        Text(editorName).foregroundStyle(Theme.ashMuted)
                        Button("Choose…", action: chooseEditor)
                        if !editorPath.isEmpty { Button("RawBoy, darktable or default") { editorPath = "" } }
                    }
                }
                Toggle(
                    "Ask before moving photos to the Trash in the browser",
                    isOn: Binding(
                        get: { !trashPhotosWithoutAsking }, set: { trashPhotosWithoutAsking = !$0 }))
                Toggle(
                    "Ask before moving to the Trash in a synced folder",
                    isOn: Binding(
                        get: { !trashNoticeShown }, set: { trashNoticeShown = !$0 }))
                LabeledContent("Send to") {
                    VStack(alignment: .trailing, spacing: 4) {
                        ForEach(sendApps, id: \.self) { url in
                            HStack {
                                Text(SendToApps.name(of: url)).foregroundStyle(Theme.ashMuted)
                                Button("Remove") {
                                    SendToApps.remove(url)
                                    sendApps = SendToApps.apps
                                }
                            }
                        }
                        Button("Add app…") {
                            if let url = SendToApps.chooseApp() {
                                SendToApps.add(url)
                                sendApps = SendToApps.apps
                            }
                        }
                    }
                }
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
