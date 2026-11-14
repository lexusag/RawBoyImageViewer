import AppKit
import Observation
import RawBoyBrowseKit
import ViewerImaging

/// What the edge panels show and the commands they send, for the open folder.
@MainActor
@Observable
final class ViewerModel {
    var folder: URL?
    /// The folder's photos (a RAW + JPEG pair is one).
    var groups: [PhotoGroup] = []
    var index = 0
    /// The current photo's full size in pixels, once loaded.
    var fullSize: Size2D?
    var fileSize: Int64?
    /// The current photo's EXIF, once read.
    var metadata: PhotoMetadata?
    var modified: Date?
    var pinned: Set<PanelEdge> = []
    var isFit = true
    var isScreenFilling = true

    let thumbnails = ThumbnailStore()
    /// Set by the session.
    var send: (ViewerCommand) -> Void = { _ in }
    var openFolder: (URL) -> Void = { _ in }

    var current: PhotoGroup? { groups.indices.contains(index) ? groups[index] : nil }

    func url(of group: PhotoGroup) -> URL? { folder?.appendingPathComponent(group.main) }
    var currentURL: URL? { current.flatMap(url(of:)) }

    /// The external editor: darktable when installed, else the photo's default app.
    let editor: (name: String, url: URL?) = {
        for id in ["org.darktable.darktable", "org.darktable"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return (url.deletingPathExtension().lastPathComponent, url)
            }
        }
        return ("default app", nil)
    }()
}
