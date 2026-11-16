import AppKit
import SwiftUI

/// What a double-click on a window's top bar does, from the system setting "Double-click a window's title bar to"
/// (System Settings › Desktop & Dock): `AppleActionOnDoubleClick` is "Maximize" (the default; also unset), "Minimize"
/// or "None".
enum TitleBarAction: Equatable {
    case zoom, minimize, nothing

    static func from(setting: String?) -> TitleBarAction {
        switch setting {
        case "Minimize": .minimize
        case "None": .nothing
        default: .zoom
        }
    }

    static var current: TitleBarAction {
        from(setting: UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick"))
    }
}

extension View {
    /// Makes this bar behave like the title bar the window doesn't have (the browser hides it): a double-click expands
    /// the window to fit the screen and a second one puts it back (the system's Zoom), and a drag moves the window.
    /// Controls on the bar take their own clicks; only the empty parts reach this.
    func titleBarZoom() -> some View { background(TitleBarZoom()) }
}

private struct TitleBarZoom: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { BarView() }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class BarView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return super.mouseDown(with: event) }
            guard event.clickCount == 2 else { return window.performDrag(with: event) }
            switch TitleBarAction.current {
            case .zoom where window.styleMask.contains(.resizable) && !window.styleMask.contains(.fullScreen):
                window.zoom(nil)
            case .minimize: window.miniaturize(nil)
            default: break
            }
        }
    }
}
