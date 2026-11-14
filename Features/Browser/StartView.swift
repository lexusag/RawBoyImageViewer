import AppKit
import SwiftUI
import ViewerFiles

/// The first screen until the browser exists (M3): pick a folder and see what's in it.
struct StartView: View {
    @State private var folder: URL?
    @State private var photos: [PhotoFile] = []
    @State private var error: String?

    var body: some View {
        ZStack {
            Theme.inkBlack.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("RawBoy Viewer")
                    .font(Theme.display)
                    .foregroundStyle(Theme.paperWhite)
                if let folder {
                    Text("\(folder.lastPathComponent): \(summary)")
                        .font(Theme.body)
                        .foregroundStyle(Theme.ashMuted)
                } else {
                    Text("Open a folder of photos.")
                        .font(Theme.body)
                        .foregroundStyle(Theme.ashMuted)
                }
                if let error {
                    Text(error)
                        .font(Theme.label)
                        .foregroundStyle(Theme.warningRed)
                }
                Button("Open folder…", action: openFolder)
                    .buttonStyle(.rawBoyPrimary)
                    .keyboardShortcut("o")
            }
            .padding(24)
        }
    }

    private var summary: String {
        let raws = photos.filter { $0.type == .raw }.count
        return "\(photos.count) files, \(raws) raw"
    }

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url
        do {
            photos = try FolderScanner.photos(in: url)
            error = nil
        } catch {
            photos = []
            self.error = "Can't read this folder: \(error.localizedDescription)"
        }
    }
}
