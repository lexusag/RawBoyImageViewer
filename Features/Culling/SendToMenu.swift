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
            if SendToApps.rawBoyDesktop != nil {
                Button("RawBoy Auto") {
                    if let folder {
                        app.sendToAuto([folder])
                    } else if let base = app.browser.folder {
                        app.sendToAuto((ids ?? app.actionTargets).map { base.appendingPathComponent($0) })
                    }
                }
            }
            if apps.isEmpty { Text("No apps yet: add them in Settings") }
        }
    }
}
