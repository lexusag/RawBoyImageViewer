import SwiftUI

/// The first screen until the browser exists (M3): open a folder or a photo, and the viewer takes over.
struct StartView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            Theme.inkBlack.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("RawBoy Viewer")
                    .font(Theme.display)
                    .foregroundStyle(Theme.paperWhite)
                Text("Open a folder of photos, or drop one here.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.ashMuted)
                if let error = model.openError {
                    Text(error)
                        .font(Theme.label)
                        .foregroundStyle(Theme.warningRed)
                }
                Button("Open…") { model.openFolderPanel() }
                    .buttonStyle(.rawBoyPrimary)
            }
            .padding(24)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.open(url)
            return true
        }
    }
}
