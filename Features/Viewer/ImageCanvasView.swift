import AppKit
import QuartzCore
import RawBoyBrowseKit
import ViewerImaging

/// Shows one photo: fit or zoomed, panned with drags, scrolls and pinches. Navigation goes out through [onCommand].
///
/// Mouse wheel: previous/next while the photo fits, zoom at the pointer once zoomed in (PLAN.md §2).
/// Trackpad: a horizontal two-finger swipe goes to previous/next while the photo fits, and pans once zoomed in.
final class ImageCanvasView: NSView {
    var onCommand: ((ViewerCommand) -> Void)?
    /// Asked for when the zoom shows more detail than the screen-size preview has.
    var onNeedsFullResolution: (() -> Void)?

    private let imageLayer = CALayer()
    private let zoomLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    private(set) var image: LoadedImage?
    private var zoom = ZoomState(scale: 1)
    /// The photo is at fit and stays fitted through window resizes.
    private var fitted = true
    private var swipeDistance = 0.0
    private var swipeFired = false
    private var zoomLabelHide: DispatchWorkItem?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: DesignTokens.Colour.inkBlack).cgColor
        imageLayer.contentsGravity = .resize
        imageLayer.minificationFilter = .trilinear
        layer?.addSublayer(imageLayer)

        zoomLabel.font = .monospacedDigitSystemFont(ofSize: DesignTokens.FontSize.label, weight: .medium)
        zoomLabel.textColor = NSColor(hex: DesignTokens.Colour.paperWhite)
        zoomLabel.wantsLayer = true
        zoomLabel.layer?.backgroundColor = NSColor(hex: DesignTokens.Colour.graphiteSurface).cgColor
        zoomLabel.layer?.cornerRadius = DesignTokens.Radius.chip
        zoomLabel.alignment = .center
        zoomLabel.alphaValue = 0

        messageLabel.font = .systemFont(ofSize: DesignTokens.FontSize.body)
        messageLabel.textColor = NSColor(hex: DesignTokens.Colour.warningRed)
        messageLabel.isHidden = true

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        for view in [zoomLabel, messageLabel, spinner] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            zoomLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            zoomLabel.topAnchor.constraint(equalTo: topAnchor, constant: DesignTokens.Spacing.xl),
            zoomLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),
            messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignTokens.Spacing.xl),
            spinner.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DesignTokens.Spacing.xl),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    // MARK: Showing photos

    /// Shows [image]. A new photo starts at fit; the full-resolution version of the photo already shown keeps the zoom.
    func show(_ image: LoadedImage, samePhoto: Bool) {
        let keepZoom = samePhoto && self.image != nil
        self.image = image
        messageLabel.isHidden = true
        setLoading(false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image.cgImage
        imageLayer.isHidden = false
        CATransaction.commit()
        if let math {
            setZoom(keepZoom ? math.clamped(zoom) : math.fit, showLabel: false)
        }
    }

    /// Clears the photo and says why.
    func showMessage(_ text: String) {
        image = nil
        imageLayer.contents = nil
        imageLayer.isHidden = true
        setLoading(false)
        messageLabel.stringValue = text
        messageLabel.isHidden = false
    }

    func setLoading(_ loading: Bool) {
        if loading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    // MARK: Zoom

    private var math: ZoomMath? {
        guard let image, bounds.width > 0, bounds.height > 0 else { return nil }
        return ZoomMath(
            imageSize: image.fullSize,
            viewSize: Size2D(width: bounds.width, height: bounds.height),
            backingScale: Double(window?.backingScaleFactor ?? 2))
    }

    var isFit: Bool { fitted }

    override func layout() {
        super.layout()
        guard let math else { return }
        // A resize keeps a fitted photo fitted.
        setZoom(fitted ? math.fit : math.clamped(zoom), showLabel: false)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    private func setZoom(_ state: ZoomState, showLabel: Bool = true) {
        zoom = state
        fitted = math?.isFit(state) ?? true
        applyZoom(showLabel: showLabel)
    }

    private func applyZoom(showLabel: Bool) {
        guard let image, let math else { return }
        let width = image.fullSize.width * zoom.scale
        let height = image.fullSize.height * zoom.scale
        let frame = CGRect(
            x: bounds.midX + zoom.offset.x - width / 2,
            y: bounds.midY + zoom.offset.y - height / 2,
            width: width, height: height)
        let previewRatio =
            Double(max(image.cgImage.width, image.cgImage.height))
            / max(image.fullSize.width, image.fullSize.height)
        let devicePixels = math.devicePixelsPerImagePixel(zoom)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = backingAligned(frame)
        // Past 1:1, show the pixels as pixels.
        imageLayer.magnificationFilter = devicePixels > 1.01 ? .nearest : .linear
        CATransaction.commit()
        if devicePixels > previewRatio * 1.01, !image.isFullResolution {
            onNeedsFullResolution?()
        }
        if showLabel {
            flashZoomLabel(math.isFit(zoom) ? "Fit" : "\(Int((devicePixels * 100).rounded()))%")
        }
        window?.invalidateCursorRects(for: self)
    }

    private func backingAligned(_ rect: CGRect) -> CGRect {
        let aligned = backingAlignedRect(rect, options: .alignAllEdgesNearest)
        // Keep the size exact when it is close: rounding both edges can stretch the photo by a pixel.
        return abs(aligned.width - rect.width) < 1 && abs(aligned.height - rect.height) < 1
            ? CGRect(origin: aligned.origin, size: rect.size) : aligned
    }

    private func flashZoomLabel(_ text: String) {
        zoomLabel.stringValue = "  \(text)  "
        zoomLabelHide?.cancel()
        zoomLabel.alphaValue = 1
        let hide = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self?.zoomLabel.animator().alphaValue = 0
            }
        }
        zoomLabelHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: hide)
    }

    /// [point] (window coordinates) relative to the view centre.
    private func anchor(_ event: NSEvent) -> Point2D {
        let p = convert(event.locationInWindow, from: nil)
        return Point2D(x: p.x - bounds.midX, y: p.y - bounds.midY)
    }

    func toggleZoom(at anchor: Point2D? = nil) {
        guard let math else { return }
        setZoom(math.toggled(zoom, around: anchor ?? .zero))
    }

    // MARK: Input

    override func keyDown(with event: NSEvent) {
        guard let command = ViewerKeys.command(for: event) else { return super.keyDown(with: event) }
        if command == .toggleZoom {
            toggleZoom()
        } else {
            onCommand?(command)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            toggleZoom(at: anchor(event))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let math, !math.isFit(zoom) else { return }
        setZoom(math.panned(zoom, by: Point2D(x: event.deltaX, y: -event.deltaY)), showLabel: false)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let math else { return }
        if event.hasPreciseScrollingDeltas {
            trackpadScroll(event, math)
        } else {
            wheelScroll(event, math)
        }
    }

    private func trackpadScroll(_ event: NSEvent, _ math: ZoomMath) {
        if event.phase == .began {
            swipeDistance = 0
            swipeFired = false
        }
        if !math.isFit(zoom) {
            setZoom(
                math.panned(zoom, by: Point2D(x: event.scrollingDeltaX, y: -event.scrollingDeltaY)), showLabel: false)
            return
        }
        // Fitted: one swipe = one photo. Momentum after the fingers lift is ignored.
        guard event.momentumPhase.isEmpty, !swipeFired else { return }
        // With natural scrolling the deltas follow the fingers; fingers moving left bring the next photo.
        let fingers = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        swipeDistance += fingers
        if abs(swipeDistance) > 60, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            swipeFired = true
            onCommand?(swipeDistance < 0 ? .next : .previous)
        }
    }

    private func wheelScroll(_ event: NSEvent, _ math: ZoomMath) {
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        if math.isFit(zoom) {
            onCommand?(delta < 0 ? .next : .previous)
        } else {
            let factor = delta > 0 ? 1.25 : 1 / 1.25
            setZoom(math.zoomed(zoom, to: zoom.scale * factor, around: anchor(event)))
        }
    }

    override func magnify(with event: NSEvent) {
        guard let math else { return }
        setZoom(math.zoomed(zoom, to: zoom.scale * (1 + event.magnification), around: anchor(event)))
    }

    override func smartMagnify(with event: NSEvent) {
        toggleZoom(at: anchor(event))
    }

    override func resetCursorRects() {
        if !isFit {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}
