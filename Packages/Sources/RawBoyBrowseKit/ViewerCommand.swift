import Foundation

/// What can be done with photos' files (the app decides how: sheets, panels, the system's share menu).
public enum FileAction: Equatable, Sendable {
    case export, copyTo, moveTo, clipboard, share, collage
    /// Open in the app at this path (Send to).
    case sendTo(String)
    /// Add to RawBoy Desktop's Auto batch as Looks, Film or As is; nil asks.
    case sendToAuto(AutoImport?)
}

/// How RawBoy Auto takes photos sent to it (its "New photos" choice): a film LUT on the automatic develop, developed as
/// film, or as they are (no automatic edits; raws get only their measured denoise).
public enum AutoImport: String, CaseIterable, Equatable, Sendable {
    case looks, film, plain

    public var label: String {
        switch self {
        case .looks: "Looks"
        case .film: "Film"
        case .plain: "As is"
        }
    }

    /// RawBoy Desktop's link for adding [paths] (photos and folders) to Auto's batch this way:
    /// `rawboy-desktop://auto?as=film&path=/a/b.RAF&path=…`.
    public func link(_ paths: [String]) -> URL? {
        var link = URLComponents()
        link.scheme = "rawboy-desktop"
        link.host = "auto"
        link.queryItems =
            [URLQueryItem(name: "as", value: rawValue)] + paths.map { URLQueryItem(name: "path", value: $0) }
        return link.url
    }
}

/// What the viewer can be asked to do, whatever the input (keys, mouse, trackpad, touch, a panel's button). Each
/// platform maps its own events onto these.
public enum ViewerCommand: Equatable, Sendable {
    case next
    case previous
    case first
    case last
    case go(to: Int)
    /// Fit ↔ 1:1 at the pointer (or the centre).
    case toggleZoom
    /// Esc: closes showing panels first, then the viewer.
    case dismiss
    /// Back to the start screen (the browser, later).
    case close
    /// Screen-filling ↔ ordinary window.
    case toggleFullScreen
    /// I, M, B (or a swipe in from the edge): show or hide an edge's panel.
    case togglePanel(PanelEdge)
    case togglePin(PanelEdge)
    /// Tab: hide every panel, pinned ones too.
    case toggleChrome
    /// J (or a click on the histogram): show clipped highlights red and crushed shadows blue, as RawBoy does.
    case toggleClipping
    /// 1–5 (0: none): stars; the same number again clears them.
    case setStars(Int)
    /// P / X: pick or reject; the same key again unflags.
    case toggleFlag(Flag)
    /// U.
    case unflag
    /// [ / ]: a quarter turn, lossless (kept in the sidecar).
    case rotate(clockwise: Bool)
    /// R: raws developed by macOS instead of the camera's embedded JPEG (RawBoy Browser's "real previews").
    case toggleRealPreview
    /// S: a slideshow from the photo on screen.
    case toggleSlideshow
    /// C: compare the photo on screen with the next ones.
    case compare
    /// K: draw a crop (kept RawBoy's way, in the sidecar).
    case crop
    /// ⌘Z: the last rating, move to the bin or to the Trash.
    case undo
    /// ⌘⌫.
    case moveToTrash
    /// Export, copy or move the photo, put it on the clipboard, share it.
    case file(FileAction)
    /// Show the photo's file in the file manager.
    case revealFile
    /// Open the photo in the external editor.
    case openInEditor
}
