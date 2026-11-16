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
    /// The levels of the picture on screen, once counted.
    var histogram: Histogram?
    /// The clipping warning is over the photo (J). Stays on from photo to photo.
    var showClipping = false
    /// Raws developed by macOS instead of the camera's JPEG (R). Off at first, as in RawBoy Browser; remembered.
    var realPreview: Bool = ViewerSettings.current.bool(forKey: "viewer.realPreview") {
        didSet { ViewerSettings.current.set(realPreview, forKey: "viewer.realPreview") }
    }
    /// A slideshow is running.
    var isSlideshow = false
    var modified: Date?
    var pinned: Set<PanelEdge> = []
    var isFit = true
    var isScreenFilling = true

    let thumbnails = ThumbnailStore()
    let culling: CullingStore

    init(culling: CullingStore) {
        self.culling = culling
    }

    /// The current photo's rating.
    var rating: Rating { current.map { culling.rating($0.main) } ?? .none }
    /// Set by the session.
    var send: (ViewerCommand) -> Void = { _ in }
    var openFolder: (URL) -> Void = { _ in }

    var current: PhotoGroup? { groups.indices.contains(index) ? groups[index] : nil }

    func url(of group: PhotoGroup) -> URL? { folder?.appendingPathComponent(group.main) }
    var currentURL: URL? { current.flatMap(url(of:)) }

    /// The external editor: the one chosen in Settings, else RawBoy Desktop when installed, else darktable, else the
    /// photo's default app. RawBoy Desktop reads and writes the same sidecars, so its edits show up here.
    var editor: (name: String, url: URL?) {
        if let path = ViewerSettings.current.string(forKey: SettingsKeys.editorPath), !path.isEmpty,
            FileManager.default.fileExists(atPath: path)
        {
            let url = URL(fileURLWithPath: path)
            return (url.deletingPathExtension().lastPathComponent, url)
        }
        return ViewerHost.handOff.editor
    }
}
