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
