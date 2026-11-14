import AppKit
import Observation

/// App-wide state shared by the SwiftUI start screen and the AppKit viewer.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let viewer = ViewerSession()
    /// Why the last open failed, for the start screen.
    var openError: String?

    func open(_ url: URL) {
        do {
            try viewer.open(url)
            openError = nil
        } catch {
            openError = error.localizedDescription
        }
    }

    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder of photos, or one photo in it."
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }
}
