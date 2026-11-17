import RawBoyBrowseKit
import SwiftUI

/// "Send to ▸": the apps from Settings, for the photos in [ids], or for a folder when [folder] is set.
struct SendToMenu: View {
    let app: AppModel
    var ids: [String]?
    var folder: URL?

    var body: some View {
        let apps = SendToApps.apps
        Menu("Send to") {
            ForEach(apps, id: \.self) { target in
                Button(SendToApps.name(of: target)) {
                    if let folder {
                        app.send([folder], to: target)
                    } else {
                        app.perform(.sendTo(target.path), ids)
                    }
                }
            }
            if ViewerHost.handOff.canSendToAuto {
                Menu("RawBoy Auto") {
                    ForEach(AutoImport.allCases, id: \.self) { how in
                        Button(how.label) {
                            if let folder {
                                app.sendToAuto([folder], as: how)
                            } else if let base = app.browser.folder {
                                let urls = (ids ?? app.actionTargets).map { base.appendingPathComponent($0) }
                                app.sendToAuto(urls, as: how)
                            }
                        }
                    }
                }
            }
            if apps.isEmpty { Text("No apps yet: add them in Settings") }
        }
    }
}

/// The two top-level entries of a photo's right-click menu: send to the editor (RawBoy Pro in Desktop) and to RawBoy
/// Auto as Looks, Film or As is. Any file type the host takes: raws, JPEG, HEIC, PNG, TIFF.
struct EditorAndAutoMenu: View {
    let app: AppModel
    let ids: [String]

    var body: some View {
        Button("Send to \(app.viewer.model.editor.name)") { app.openInEditor(ids) }
        if ViewerHost.handOff.canSendToAuto {
            Menu("Send to RawBoy Auto") {
                ForEach(AutoImport.allCases, id: \.self) { how in
                    Button(how.label) { app.perform(.sendToAuto(how), ids) }
                }
            }
        }
    }
}
