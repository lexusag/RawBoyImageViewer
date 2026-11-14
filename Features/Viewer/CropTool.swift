import AppKit
import Observation
import RawBoyBrowseKit
import SwiftUI

/// The crop being drawn, shared by the overlay and its toolbar.
@MainActor
@Observable
final class CropToolState {
    var crop: CropRect
    var aspect: CropAspect = .free {
        didSet { applyAspect() }
    }
    var portrait: Bool {
        didSet { applyAspect() }
    }
    /// The turned photo's size in pixels (aspect ratios are in pixels).
    let frameSize: Size2D
    var onDone: (CropRect) -> Void = { _ in }
    var onCancel: () -> Void = {}
    var changed: () -> Void = {}

    init(crop: CropRect, frameSize: Size2D) {
        self.crop = crop
        self.frameSize = frameSize
        portrait = frameSize.height > frameSize.width
    }

    var ratio: Double? { aspect.ratio(frameWidth: frameSize.width, frameHeight: frameSize.height, portrait: portrait) }

    private func applyAspect() {
        crop = CropMath.withAspect(crop, ratio: ratio, frameWidth: frameSize.width, frameHeight: frameSize.height)
        changed()
    }

    func reset() {
        aspect = .free
        crop = .full
        changed()
    }
}

/// Draws the crop over the whole photo and lets it be dragged: corners and edges resize (keeping the aspect when one
/// is chosen), inside moves. Outside the crop is darkened; thirds lines inside. Return applies, Esc cancels.
final class CropOverlayView: NSView {
    let state: CropToolState
    /// Where the whole picture is, in this view's coordinates.
    var imageRect: () -> CGRect = { .zero }
    private var dragHandle: CropHandle?
    private var dragStart: (point: CGPoint, crop: CropRect)?

    init(state: CropToolState) {
        self.state = state
        super.init(frame: .zero)
        state.changed = { [weak self] in self?.needsDisplay = true }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// The crop in this view's coordinates.
    private var cropRect: CGRect {
        let r = imageRect()
        let c = state.crop
        return CGRect(
            x: r.minX + c.left * r.width, y: r.minY + c.top * r.height, width: c.width * r.width,
            height: c.height * r.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let image = imageRect()
        let crop = cropRect
        // Outside the crop, over the photo: darkened.
        let outside = NSBezierPath(rect: image)
        outside.append(NSBezierPath(rect: crop))
        outside.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.6).setFill()
        outside.fill()
        // Thirds.
        NSColor.white.withAlphaComponent(0.35).setStroke()
        for k in 1...2 {
            let x = crop.minX + crop.width * Double(k) / 3
            let y = crop.minY + crop.height * Double(k) / 3
            let lines = NSBezierPath()
            lines.move(to: CGPoint(x: x, y: crop.minY))
            lines.line(to: CGPoint(x: x, y: crop.maxY))
            lines.move(to: CGPoint(x: crop.minX, y: y))
            lines.line(to: CGPoint(x: crop.maxX, y: y))
            lines.lineWidth = 1
            lines.stroke()
        }
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: crop.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
        // Corner handles.
        let l = min(20, crop.width / 3, crop.height / 3)
        let corners = NSBezierPath()
        for (x, y, sx, sy) in [
            (crop.minX, crop.minY, 1.0, 1.0), (crop.maxX, crop.minY, -1.0, 1.0), (crop.minX, crop.maxY, 1.0, -1.0),
            (crop.maxX, crop.maxY, -1.0, -1.0),
        ] {
            corners.move(to: CGPoint(x: x + sx * l, y: y))
            corners.line(to: CGPoint(x: x, y: y))
            corners.line(to: CGPoint(x: x, y: y + sy * l))
        }
        corners.lineWidth = 4
        corners.stroke()
    }

    private func fractions(_ p: CGPoint) -> (Double, Double) {
        let r = imageRect()
        return ((p.x - r.minX) / max(r.width, 1), (p.y - r.minY) / max(r.height, 1))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        let (x, y) = fractions(p)
        let r = imageRect()
        dragHandle = CropMath.handle(
            at: state.crop, x: x, y: y, tolX: 14 / max(r.width, 1), tolY: 14 / max(r.height, 1))
        dragStart = (p, state.crop)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let handle = dragHandle, let start = dragStart else { return }
        let p = convert(event.locationInWindow, from: nil)
        let r = imageRect()
        state.crop = CropMath.drag(
            start.crop, handle, dx: (p.x - start.point.x) / max(r.width, 1),
            dy: (p.y - start.point.y) / max(r.height, 1),
            ratio: state.ratio, frameWidth: state.frameSize.width, frameHeight: state.frameSize.height)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragHandle = nil
        dragStart = nil
    }

    override func resetCursorRects() {
        let c = cropRect
        let t = 8.0
        addCursorRect(c.insetBy(dx: t, dy: t), cursor: .openHand)
        addCursorRect(
            CGRect(x: c.minX - t, y: c.minY + t, width: 2 * t, height: c.height - 2 * t), cursor: .resizeLeftRight)
        addCursorRect(
            CGRect(x: c.maxX - t, y: c.minY + t, width: 2 * t, height: c.height - 2 * t), cursor: .resizeLeftRight)
        addCursorRect(
            CGRect(x: c.minX + t, y: c.minY - t, width: c.width - 2 * t, height: 2 * t), cursor: .resizeUpDown)
        addCursorRect(
            CGRect(x: c.minX + t, y: c.maxY - t, width: c.width - 2 * t, height: 2 * t), cursor: .resizeUpDown)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: state.onDone(state.crop)  // Return, Enter
        case 53: state.onCancel()  // Esc
        default: super.keyDown(with: event)
        }
    }
}

/// Under the photo while cropping: aspect, orientation, reset, cancel, done.
struct CropToolbar: View {
    @Bindable var state: CropToolState

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Segmented(
                options: [CropAspect.free, .original, .square, .fiveFour, .fourThree, .threeTwo, .sixteenNine].map {
                    ($0, $0.label(portrait: state.portrait))
                }, selection: $state.aspect)
            Button {
                state.portrait.toggle()
            } label: {
                Image(systemName: state.portrait ? "rectangle.portrait" : "rectangle")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.rawBoy)
            .help(state.portrait ? "Portrait: switch to landscape" : "Landscape: switch to portrait")
            .disabled(state.aspect == .free || state.aspect == .square)
            Button("Reset") { state.reset() }.buttonStyle(.rawBoy)
            Button("Cancel") { state.onCancel() }.buttonStyle(.rawBoy)
            Button("Done") { state.onDone(state.crop) }.buttonStyle(.rawBoyPrimary)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.card).fill(Theme.graphiteSurface))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.card).strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
        .fixedSize()
    }
}
