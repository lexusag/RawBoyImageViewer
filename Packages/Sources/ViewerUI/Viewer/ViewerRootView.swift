import AppKit
import RawBoyBrowseKit
import SwiftUI

/// The viewer window's content: the photo canvas, and the three edge panels floating over it. Flipped (y down), the
/// same coordinates as `EdgeZones`.
final class ViewerRootView: NSView {
    let canvas = ImageCanvasView(frame: .zero)
    private(set) var panels: [PanelEdge: NSView] = [:]
    /// Panels that show (or are fading in).
    private var shown: Set<PanelEdge> = []
    private var reserved: Set<PanelEdge> = []
    /// Called with the pointer (nil: it left the window) on every move.
    var onPointer: ((Point2D?) -> Void)?
    /// Called when the view enters or leaves a window (a host's, when the viewer isn't in a window of its own).
    var onWindowChange: ((NSWindow?) -> Void)?

    static let margin = 12.0
    static let sideWidth: [PanelEdge: Double] = [.left: 280, .right: 320]
    static let topHeight = 136.0

    init(model: ViewerModel) {
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(canvas)
        let views: [PanelEdge: AnyView] = [
            .left: AnyView(ActionMenu(model: model)),
            .right: AnyView(InfoPanel(model: model)),
            .top: AnyView(BrowserStrip(model: model)),
        ]
        for (edge, view) in views {
            let host = NSHostingView(rootView: view.preferredColorScheme(.dark))
            host.sizingOptions = []
            host.isHidden = true
            host.alphaValue = 0
            addSubview(host)
            panels[edge] = host
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }

    // MARK: Layout

    /// Where [edge]'s panel sits when showing.
    func frame(for edge: PanelEdge) -> CGRect {
        let m = Self.margin
        switch edge {
        case .left:
            return CGRect(x: m, y: m, width: Self.sideWidth[.left]!, height: bounds.height - 2 * m)
        case .right:
            let w = Self.sideWidth[.right]!
            return CGRect(x: bounds.width - m - w, y: m, width: w, height: bounds.height - 2 * m)
        case .top:
            // Between pinned side panels, so a pinned panel is never covered.
            let left = reserved.contains(.left) ? m + Self.sideWidth[.left]! + m : m
            let right = reserved.contains(.right) ? bounds.width - m - Self.sideWidth[.right]! - m : bounds.width - m
            return CGRect(x: left, y: m, width: max(right - left, 200), height: Self.topHeight)
        }
    }

    /// Off-screen-ward start of the slide-in (reduced motion: no slide, just a fade).
    private func hiddenFrame(for edge: PanelEdge) -> CGRect {
        let frame = frame(for: edge)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return frame }
        let d = 16.0
        switch edge {
        case .left: return frame.offsetBy(dx: -d, dy: 0)
        case .right: return frame.offsetBy(dx: d, dy: 0)
        case .top: return frame.offsetBy(dx: 0, dy: -d)
        }
    }

    /// Panel frames as they show, y down, for the grace margin.
    var panelRects: [PanelEdge: Rect2D] {
        var rects: [PanelEdge: Rect2D] = [:]
        for edge in shown {
            let f = frame(for: edge)
            rects[edge] = Rect2D(x: f.minX, y: f.minY, width: f.width, height: f.height)
        }
        return rects
    }

    override func layout() {
        super.layout()
        canvas.frame = bounds
        canvas.contentInsets = insets(for: reserved)
        for (edge, view) in panels {
            view.frame = shown.contains(edge) ? frame(for: edge) : hiddenFrame(for: edge)
        }
    }

    /// The room pinned panels take from the photo (canvas coordinates: y up).
    private func insets(for edges: Set<PanelEdge>) -> NSEdgeInsets {
        let m = Self.margin
        return NSEdgeInsets(
            top: edges.contains(.top) ? m + Self.topHeight + m : 0,
            left: edges.contains(.left) ? m + Self.sideWidth[.left]! + m : 0,
            bottom: 0,
            right: edges.contains(.right) ? m + Self.sideWidth[.right]! + m : 0)
    }

    /// Shows [visible] panels and fits the photo beside [reserved] ones.
    func apply(visible: Set<PanelEdge>, reserved: Set<PanelEdge>) {
        let reservedChanged = reserved != self.reserved
        self.reserved = reserved
        if reservedChanged {
            canvas.contentInsets = insets(for: reserved)
        }
        let fade = 0.15
        for (edge, view) in panels {
            let show = visible.contains(edge)
            guard show != shown.contains(edge) || (show && reservedChanged) else { continue }
            if show {
                let appearing = !shown.contains(edge)
                shown.insert(edge)
                let target = frame(for: edge)
                if appearing {
                    view.isHidden = false
                    // Move the frame at once and slide the layer: animating an NSHostingView's frame makes SwiftUI
                    // lay the panel out on every step, which showed as ghosted text and a half-transparent card.
                    let from = hiddenFrame(for: edge)
                    view.frame = target
                    slide(view, dx: from.minX - target.minX, dy: from.minY - target.minY, duration: fade)
                } else {
                    view.frame = target
                }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = fade
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    view.animator().alphaValue = 1
                } completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        // Never leave a panel part-way through a fade (an interrupted animation did).
                        if self?.shown.contains(edge) == true { view.alphaValue = 1 }
                    }
                }
            } else {
                shown.remove(edge)
                let target = hiddenFrame(for: edge)
                let now = frame(for: edge)
                slide(view, dx: target.minX - now.minX, dy: target.minY - now.minY, duration: fade, toOffset: true)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = fade
                    view.animator().alphaValue = 0
                } completionHandler: { [weak self] in
                    MainActor.assumeIsolated {
                        if self?.shown.contains(edge) == false {
                            view.isHidden = true
                            view.alphaValue = 0
                            view.layer?.removeAllAnimations()
                        }
                    }
                }
            }
        }
    }

    /// Slides a panel's layer by an offset (from it to rest, or from rest to it) without touching the view's frame.
    private func slide(_ view: NSView, dx: Double, dy: Double, duration: Double, toOffset: Bool = false) {
        guard let layer = view.layer, dx != 0 || dy != 0 else { return }
        // The root is flipped (y down) but layers of its subviews follow the view's own geometry: y down too.
        let offset = CATransform3DMakeTranslation(dx, dy, 0)
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = toOffset ? CATransform3DIdentity : offset
        animation.toValue = toOffset ? offset : CATransform3DIdentity
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "slide")
    }

    // MARK: Pointer

    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        report(event)
        super.mouseMoved(with: event)
    }

    override func mouseEntered(with event: NSEvent) { report(event) }
    override func mouseExited(with event: NSEvent) { onPointer?(nil) }

    func report(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        onPointer?(Point2D(x: p.x, y: p.y))
    }
}
