import AppKit
import RawBoyBrowseKit
import SwiftUI
import ViewerImaging

/// The browser's optional pane on the right: the photo at the anchor, large, with its name, date and size. The
/// picture is a screen-size preview (a raw's embedded JPEG), made shortly after the selection settles so arrow keys
/// stay fast.
struct PreviewPane: View {
    let app: AppModel
    @State private var image: CGImage?
    @State private var loadedID: String?
    @State private var pixelSize: Size2D?

    var body: some View {
        let browser = app.browser
        let photo = browser.anchor.flatMap { id in browser.visible.first { $0.id == id } }
        let orientation = photo.flatMap { app.culling.orientation($0.id) }
        VStack(spacing: 0) {
            ZStack {
                Theme.inkBlack
                if let photo, loadedID == photo.id, let image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                        .padding(DesignTokens.Spacing.sm)
                } else if let photo, photo.isOnlineOnly {
                    Text("Only in the cloud: opening it downloads it")
                        .font(Theme.label).foregroundStyle(Theme.ashMuted)
                } else if photo == nil {
                    Text("Select a photo").font(Theme.label).foregroundStyle(Theme.ashMuted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let photo {
                VStack(alignment: .leading, spacing: 2) {
                    Text(photo.name).font(Theme.body).foregroundStyle(Theme.paperWhite)
                        .lineLimit(1).truncationMode(.middle)
                    Text(details(photo)).font(Theme.label).foregroundStyle(Theme.ashMuted).lineLimit(1)
                    if loadedID == photo.id, let pixelSize {
                        Text(InfoPanel.dimensions(pixelSize)).font(Theme.label).foregroundStyle(Theme.ashMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignTokens.Spacing.md)
                .background(Theme.graphiteSurface)
            }
        }
        .padding(.top, 34)  // under the window's traffic lights
        .background(Theme.inkBlack)
        .task(id: "\(photo?.id ?? "")|\(orientation ?? 0)|\(photo?.modified?.timeIntervalSince1970 ?? 0)") {
            guard let photo, !photo.isOnlineOnly else {
                image = nil
                pixelSize = nil
                loadedID = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            let url = photo.url
            let loaded = await Task.detached(priority: .userInitiated) {
                ImageLoader.preview(of: url, maxPixelSize: 1600, orientation: orientation)
            }.value
            if Task.isCancelled { return }
            image = loaded?.cgImage
            pixelSize = loaded?.fullSize
            loadedID = photo.id
        }
    }

    private func details(_ photo: BrowsePhoto) -> String {
        [
            PhotoList.kindText(photo), PhotoList.dateText(photo.date),
            photo.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) },
        ]
        .compactMap { $0 }.joined(separator: " · ")
    }
}
