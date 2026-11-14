/// What the viewer can be asked to do, whatever the input (keys, mouse, trackpad, touch). Each platform maps its own
/// events onto these.
public enum ViewerCommand: Equatable, Sendable {
    case next
    case previous
    case first
    case last
    /// Fit ↔ 1:1 at the pointer (or the centre).
    case toggleZoom
    /// Back to the start screen (the browser, later).
    case close
    /// Screen-filling ↔ ordinary window.
    case toggleFullScreen
}
