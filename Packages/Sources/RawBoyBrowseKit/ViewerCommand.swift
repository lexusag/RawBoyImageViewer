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
    /// Show the photo's file in the file manager.
    case revealFile
    /// Open the photo in the external editor.
    case openInEditor
}
