import AppKit
import QuartzCore
import RawBoyBrowseKit
import ViewerImaging

/// Shows one photo: fit or zoomed, panned with drags, scrolls and pinches, in the area pinned panels leave free.
/// Navigation goes out through [onCommand].
///
/// - Bottom band (photo fitted): left half previous, right half next; holding repeats (PLAN.md §2).
/// - Press and hold elsewhere on a fitted photo: 1:1 at the pointer, drag to pan, release to fit again.
/// - Mouse wheel: previous/next while the photo fits, zoom at the pointer once zoomed in.
/// - Trackpad: a horizontal two-finger swipe goes to previous/next while the photo fits, and pans once zoomed in.
final class ImageCanvasView: NSView {
    var onCommand: ((ViewerCommand) -> Void)?
    /// Asked for when the zoom shows more detail than the screen-size preview has.
    var onNeedsFullResolution: (() -> Void)?
    /// Fit ↔ zoomed.
    var onFitChanged: ((Bool) -> Void)?
    /// The person zoomed or panned (Compare passes it on to the other panes).
    var onZoomChanged: ((SharedZoom) -> Void)?
    /// The part of the photo shown (RawBoy's crop, fractions of the turned photo); nil shows all of it.
    var crop: CropRect? {
        didSet {
            guard crop != oldValue else { return }
            if let math { setZoom(math.fit, showLabel: false, notify: false) }
        }
    }

    /// The photo's size as shown: cropped when there is a crop.
    private var shownSize: Size2D? {
        guard let image else { return nil }
        let c = crop ?? .full
        return Size2D(width: image.fullSize.width * c.width, height: image.fullSize.height * c.height)
    }

    /// Where the whole picture is drawn, in this view's coordinates (the crop tool draws over it).
    var imageFrame: CGRect { imageLayer.frame }

    /// A quick click (not a hold, not a double-click): Compare chooses the pane.
    var onClick: (() -> Void)?
    /// The right-click menu (nil: none).
    var onContextMenu: (() -> NSMenu?)?
    /// The bottom band, the wheel and swipes change photos. Off in Compare, which has its own keys.
    var navigationEnabled = true {
        didSet {
            guard navigationEnabled != oldValue else { return }
            if !navigationEnabled { setBandSide(nil) }
            window?.invalidateCursorRects(for: self)
        }
    }
    /// A pane's name, in its top-left corner (Compare).
    var captionText = "" {
        didSet {
            captionLabel.stringValue = "  \(captionText)  "
            captionLabel.isHidden = captionText.isEmpty
        }
    }
    /// Compare's chosen pane: an amber frame.
    var isHighlighted = false {
        didSet {
            layer?.borderColor = NSColor(hex: DesignTokens.Colour.safelightAmber).cgColor
            layer?.borderWidth = isHighlighted ? 2 : 0
        }
    }
    private let captionLabel = ImageCanvasView.pill()

    /// Room taken by pinned panels: the photo fits in what is left.
    var contentInsets = NSEdgeInsets() {
        didSet {
            guard !NSEdgeInsetsEqual(oldValue, contentInsets) else { return }
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
    }

    /// "5 / 72", shown in the bottom band.
    var counterText = "" {
        didSet { counterLabel.stringValue = "  \(counterText)  " }
    }

    private let imageLayer = CALayer()
    /// RawBoy's clipping warning, over the photo with the same frame.
    private let clipLayer = CALayer()
    private let zoomLabel = ImageCanvasView.pill()
    private let counterLabel = ImageCanvasView.pill()
    private let ratingLabel = ImageCanvasView.pill()
    private var ratingLeading: NSLayoutConstraint?

    /// The photo's rating ("★★★ · Pick"), in the photo area's bottom-left corner while it has one.
    var ratingText = "" {
        didSet {
            ratingLabel.stringValue = "  \(ratingText)  "
            ratingLabel.isHidden = ratingText.isEmpty
            ratingLabel.textColor = NSColor(
                hex: ratingText == "Rejected" ? DesignTokens.Colour.warningRed : DesignTokens.Colour.paperWhite)
        }
    }
    private let messageLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private var counterConstraint: NSLayoutConstraint?

    private(set) var image: LoadedImage?
    /// What a fit-size picture was made for: the photo (by its image), the pixels it takes and the crop.
    private struct FitKey: Equatable {
        var image: ObjectIdentifier
        var width: Int
        var height: Int
        var crop: CropRect?
    }
    /// The photo resampled to the pixels it takes at fit (Lanczos, see `FitScaler`), once made.
    private var fitCache: (key: FitKey, image: CGImage)?
    private var fitKey: FitKey?
    private var fitTask: Task<Void, Never>?
    private var zoom = ZoomState(scale: 1)
    /// The photo is at fit and stays fitted through window and panel changes.
    private var fitted = true {
        didSet { if fitted != oldValue { onFitChanged?(fitted) } }
    }
    private var swipeDistance = 0.0
    private var swipeFired = false
    private var labelHide: DispatchWorkItem?
    private var repeatTimer: Timer?
    private var bandSide: ViewerCommand?
    /// The last time the wheel or a gesture zoomed: the wheel that zoomed out to fit must not run on into the next
    /// photos, so navigation waits for a pause.
    private var lastZoomInput = 0.0
    /// Press and hold on a fitted photo: 1:1 at the pointer while the button is down, back to fit on release.
    private var peekTimer: Timer?
    private var peekAnchor: Point2D?
    private var isPeeking = false
    /// The mouse moved with the button down since it went down (a drag, not a click).
    private var didDrag = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: DesignTokens.Colour.inkBlack).cgColor
        // VoiceOver: the photo is an image named by the session (name, position, rating).
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        imageLayer.contentsGravity = .resize
        // Never trilinear: at a non-integer downscale it blends in a half-size mip level and softens the photo.
        imageLayer.minificationFilter = .linear
        layer?.addSublayer(imageLayer)
        clipLayer.contentsGravity = .resize
        clipLayer.magnificationFilter = .nearest
        clipLayer.isHidden = true
        layer?.addSublayer(clipLayer)

        zoomLabel.alphaValue = 0
        counterLabel.alphaValue = 0
        ratingLabel.isHidden = true
        captionLabel.isHidden = true

        messageLabel.font = .systemFont(ofSize: DesignTokens.FontSize.body)
        messageLabel.textColor = NSColor(hex: DesignTokens.Colour.warningRed)
        messageLabel.isHidden = true

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        for view in [zoomLabel, counterLabel, ratingLabel, captionLabel, messageLabel, spinner] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let counterX = counterLabel.centerXAnchor.constraint(equalTo: leadingAnchor)
        counterConstraint = counterX
        let ratingX = ratingLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Spacing.lg)
        ratingLeading = ratingX
        NSLayoutConstraint.activate([
            zoomLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            zoomLabel.topAnchor.constraint(equalTo: topAnchor, constant: DesignTokens.Spacing.xl),
            counterX,
            ratingX,
            captionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Spacing.md),
            captionLabel.topAnchor.constraint(equalTo: topAnchor, constant: DesignTokens.Spacing.md),
            ratingLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DesignTokens.Spacing.lg),
            counterLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DesignTokens.Spacing.lg),
            messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DesignTokens.Spacing.xl),
            spinner.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DesignTokens.Spacing.xl),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func pill() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: DesignTokens.FontSize.label, weight: .medium)
        label.textColor = NSColor(hex: DesignTokens.Colour.paperWhite)
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor(hex: DesignTokens.Colour.graphiteSurface).cgColor
        label.layer?.cornerRadius = DesignTokens.Radius.chip
        label.layer?.borderColor = NSColor(hex: DesignTokens.Colour.hairline).cgColor
        label.layer?.borderWidth = 1
        label.alignment = .center
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
        label.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return label
    }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    // MARK: Showing photos

    /// Shows [image]. A new photo starts at fit; the full-resolution version of the photo already shown keeps the zoom.
    func show(_ image: LoadedImage, samePhoto: Bool, fade: Bool = false) {
        let keepZoom = samePhoto && self.image != nil
        if fade, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            // A slideshow's crossfade.
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.6
            imageLayer.add(transition, forKey: "fade")
        }
        self.image = image
        fitTask?.cancel()
        fitCache = nil
        fitKey = nil
        messageLabel.isHidden = true
        setLoading(false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image.cgImage
        imageLayer.isHidden = false
        CATransaction.commit()
        if let math {
            setZoom(keepZoom ? math.clamped(zoom) : math.fit, showLabel: false, notify: false)
        }
    }

    var hasClipOverlay: Bool { !clipLayer.isHidden && clipLayer.contents != nil }

    /// The clipping warning for the picture on screen; nil hides it.
    func setClipOverlay(_ overlay: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clipLayer.contents = overlay
        clipLayer.isHidden = overlay == nil
        CATransaction.commit()
    }

    /// Clears the photo and says why.
    func showMessage(_ text: String) {
        image = nil
        imageLayer.contents = nil
        imageLayer.isHidden = true
        clipLayer.isHidden = true
        setLoading(false)
        messageLabel.stringValue = text
        messageLabel.isHidden = false
    }

    func setLoading(_ loading: Bool) {
        if loading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    }

    /// A short note at the top, gone after a moment (and spoken by VoiceOver).
    func flash(_ text: String) {
        NSAccessibility.post(
            element: self, notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        zoomLabel.stringValue = "  \(text)  "
        labelHide?.cancel()
        zoomLabel.alphaValue = 1
        let hide = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self?.zoomLabel.animator().alphaValue = 0
            }
        }
        labelHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9 + Double(text.count) * 0.03, execute: hide)
    }

    // MARK: Zoom

    /// The part of the view the photo may use (view coordinates, y up).
    var imageArea: CGRect {
        let i = contentInsets
        return CGRect(
            x: i.left, y: i.bottom,
            width: max(bounds.width - i.left - i.right, 1), height: max(bounds.height - i.top - i.bottom, 1))
    }

    private var math: ZoomMath? {
        guard let size = shownSize, bounds.width > 0, bounds.height > 0 else { return nil }
        let area = imageArea
        return ZoomMath(
            imageSize: size,
            viewSize: Size2D(width: area.width, height: area.height),
            backingScale: Double(window?.backingScaleFactor ?? 2))
    }

    var isFit: Bool { fitted }

    override func layout() {
        super.layout()
        counterConstraint?.constant = imageArea.midX
        ratingLeading?.constant = imageArea.minX + DesignTokens.Spacing.lg
        guard let math else { return }
        setZoom(fitted ? math.fit : math.clamped(zoom), showLabel: false, notify: false)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    private func setZoom(_ state: ZoomState, showLabel: Bool = true, notify: Bool = true) {
        let changed = state != zoom
        zoom = state
        fitted = math?.isFit(state) ?? true
        applyZoom(showLabel: showLabel)
        if notify, changed, let math { onZoomChanged?(math.shared(state)) }
    }

    /// Takes on another pane's zoom, without passing it on.
    func applyShared(_ shared: SharedZoom) {
        guard let math else { return }
        setZoom(math.state(shared), showLabel: false, notify: false)
    }

    /// The zoom as other photos can take it on.
    var sharedZoom: SharedZoom { math.map { $0.shared(zoom) } ?? .fit }

    private func applyZoom(showLabel: Bool) {
        guard let image, let math, let size = shownSize else { return }
        let area = imageArea
        let backing = math.backingScale
        let width = size.width * zoom.scale
        let height = size.height * zoom.scale
        var frame = CGRect(
            x: area.midX + zoom.offset.x - width / 2,
            y: area.midY + zoom.offset.y - height / 2,
            width: width, height: height)
        let previewRatio =
            Double(max(image.cgImage.width, image.cgImage.height)) / max(image.fullSize.width, image.fullSize.height)
        let devicePixels = math.devicePixelsPerImagePixel(zoom)
        // At fit the photo is shown pixel for pixel from a picture made for exactly that size.
        let c = crop ?? .full
        let fitPixels = fitPixelSize(frame: frame, image: image, crop: c, devicePixels: devicePixels, backing: backing)
        if let fitPixels {
            frame = CGRect(
                x: (frame.minX * backing).rounded() / backing, y: (frame.minY * backing).rounded() / backing,
                width: Double(fitPixels.width) / backing, height: Double(fitPixels.height) / backing)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = fitPixels == nil ? backingAligned(frame) : frame
        clipLayer.frame = imageLayer.frame
        // Layer contents count from the bottom-left; crops from the top-left.
        let contentsRect = CGRect(x: c.left, y: 1 - c.bottom, width: c.width, height: c.height)
        clipLayer.contentsRect = contentsRect
        // Past 1:1, show the pixels as pixels.
        imageLayer.magnificationFilter = devicePixels > 1.01 ? .nearest : .linear
        imageLayer.contents = image.cgImage
        imageLayer.contentsRect = contentsRect
        if let fitPixels {
            let key = FitKey(
                image: ObjectIdentifier(image.cgImage), width: fitPixels.width, height: fitPixels.height, crop: crop)
            if let cache = fitCache, cache.key == key {
                imageLayer.contents = cache.image
                imageLayer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                imageLayer.magnificationFilter = .nearest
                imageLayer.minificationFilter = .nearest
            } else {
                makeFitImage(key, image: image, region: contentsRect)
            }
        } else {
            fitKey = nil
            fitTask?.cancel()
            imageLayer.minificationFilter = .linear
        }
        CATransaction.commit()
        if devicePixels > previewRatio * 1.01, !image.isFullResolution {
            onNeedsFullResolution?()
        }
        if showLabel {
            flash(math.isFit(zoom) ? "Fit" : "\(Int((devicePixels * 100).rounded()))%")
        }
        window?.invalidateCursorRects(for: self)
    }

    /// The device pixels the photo takes at fit when that is a downscale of what [image] holds, else nil (zoomed, or
    /// shown at or above its own size, where the layer's filter is all it needs).
    private func fitPixelSize(
        frame: CGRect, image: LoadedImage, crop: CropRect, devicePixels: Double, backing: Double
    ) -> (width: Int, height: Int)? {
        guard fitted, devicePixels < 0.999 else { return nil }
        let w = Int((frame.width * backing).rounded())
        let h = Int((frame.height * backing).rounded())
        let sourceWidth = Double(image.cgImage.width) * crop.width
        guard w > 0, h > 0, Double(w) < sourceWidth * 0.999 else { return nil }
        return (w, h)
    }

    /// Makes the fit-size picture off the main thread and puts it on the layer when it is ready and still wanted.
    private func makeFitImage(_ key: FitKey, image: LoadedImage, region: CGRect) {
        guard fitKey != key else { return }
        fitKey = key
        fitTask?.cancel()
        let width = key.width
        let height = key.height
        fitTask = Task { [weak self] in
            let made = await Task.detached(priority: .userInitiated) {
                FitScaler.scale(image, region: region, width: width, height: height)
            }.value
            guard let self, !Task.isCancelled, let made, self.fitKey == key else { return }
            self.fitCache = (key, made.cgImage)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.imageLayer.contents = made.cgImage
            self.imageLayer.contentsRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            self.imageLayer.magnificationFilter = .nearest
            self.imageLayer.minificationFilter = .nearest
            CATransaction.commit()
        }
    }

    private func backingAligned(_ rect: CGRect) -> CGRect {
        let aligned = backingAlignedRect(rect, options: .alignAllEdgesNearest)
        // Keep the size exact when it is close: rounding both edges can stretch the photo by a pixel.
        return abs(aligned.width - rect.width) < 1 && abs(aligned.height - rect.height) < 1
            ? CGRect(origin: aligned.origin, size: rect.size) : aligned
    }

    /// The event's position relative to the photo area's centre.
    private func anchor(_ event: NSEvent) -> Point2D {
        let p = convert(event.locationInWindow, from: nil)
        let area = imageArea
        return Point2D(x: p.x - area.midX, y: p.y - area.midY)
    }

    func toggleZoom(at anchor: Point2D? = nil) {
        guard let math else { return }
        setZoom(math.toggled(zoom, around: anchor ?? .zero))
    }

    // MARK: Bottom band

    /// `.previous`/`.next` when [event] is in the bottom band and the photo fits.
    private func bandCommand(_ event: NSEvent) -> ViewerCommand? {
        bandCommand(at: convert(event.locationInWindow, from: nil))
    }

    private func bandCommand(at p: CGPoint) -> ViewerCommand? {
        guard navigationEnabled, fitted, image != nil else { return nil }
        let area = imageArea
        // To the band's coordinates: y down.
        let areaDown = Rect2D(
            x: area.minX, y: bounds.height - area.maxY, width: area.width, height: area.height)
        return BottomBand.command(at: Point2D(x: p.x, y: bounds.height - p.y), in: areaDown)
    }

    private func bandRect(_ side: ViewerCommand) -> CGRect {
        let area = imageArea
        let areaDown = Rect2D(x: area.minX, y: bounds.height - area.maxY, width: area.width, height: area.height)
        let height = BottomBand.height(of: areaDown)
        let half = area.width / 2
        return CGRect(x: side == .previous ? area.minX : area.minX + half, y: area.minY, width: half, height: height)
    }

    private func setBandSide(_ side: ViewerCommand?) {
        guard side != bandSide else { return }
        bandSide = side
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            counterLabel.animator().alphaValue = side == nil ? 0 : 1
        }
    }

    private func startRepeating(_ command: ViewerCommand) {
        repeatTimer?.invalidate()
        let timer = Timer(timeInterval: BottomBand.repeatDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onCommand?(command)
                let repeating = Timer(timeInterval: BottomBand.repeatInterval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onCommand?(command) }
                }
                RunLoop.main.add(repeating, forMode: .common)
                self.repeatTimer = repeating
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
    }

    private func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(
            NSTrackingArea(
                rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard navigationEnabled, image != nil else { return nil }
        return onContextMenu?()
    }

    override func mouseMoved(with event: NSEvent) {
        setBandSide(bandCommand(event))
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        setBandSide(nil)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        didDrag = false
        if let command = bandCommand(event) {
            // One step per click; double-clicks in the band are two steps, not a zoom.
            onCommand?(command)
            startRepeating(command)
            return
        }
        if event.clickCount == 2 {
            cancelPeek()
            if navigationEnabled {
                // A double click leaves the photo for the browser (mouse-only use); zoom stays on the wheel, a
                // press-and-hold and the pinch. Compare and the crop tool (navigation off) keep the zoom toggle.
                onCommand?(.close)
            } else {
                toggleZoom(at: anchor(event))
            }
            return
        }
        if fitted, image != nil {
            // A quick click does nothing; holding starts the 1:1 peek (dragging starts it at once).
            peekAnchor = anchor(event)
            let timer = Timer(timeInterval: Self.peekDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.startPeek() }
            }
            RunLoop.main.add(timer, forMode: .common)
            peekTimer = timer
        }
    }

    /// How long the button must stay down before a click becomes a peek.
    static let peekDelay = 0.15

    private func startPeek() {
        peekTimer?.invalidate()
        peekTimer = nil
        guard let math, fitted, let anchor = peekAnchor else { return }
        isPeeking = true
        setZoom(math.zoomed(zoom, to: math.oneToOneScale, around: anchor))
        NSCursor.closedHand.set()
    }

    private func cancelPeek() {
        peekTimer?.invalidate()
        peekTimer = nil
        peekAnchor = nil
    }

    override func mouseUp(with event: NSEvent) {
        stopRepeating()
        if !didDrag, !isPeeking, event.clickCount == 1 { onClick?() }
        cancelPeek()
        if isPeeking, let math {
            isPeeking = false
            setZoom(math.fit, showLabel: false)
            window?.invalidateCursorRects(for: self)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        didDrag = true
        if peekTimer != nil { startPeek() }
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
            lastZoomInput = event.timestamp
            setZoom(
                math.panned(zoom, by: Point2D(x: event.scrollingDeltaX, y: -event.scrollingDeltaY)), showLabel: false)
            return
        }
        guard navigationEnabled else { return }
        // Fitted: one swipe = one photo. Momentum after the fingers lift is ignored, and so is a scroll that was
        // panning a moment ago.
        guard event.momentumPhase.isEmpty, !swipeFired, event.timestamp - lastZoomInput > Self.navigationPause else {
            if event.timestamp - lastZoomInput <= Self.navigationPause { lastZoomInput = event.timestamp }
            return
        }
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
        if SettingsKeys.wheelZooms {
            // Settings: the wheel always zooms, up in, down out (down at fit stays at fit).
            lastZoomInput = event.timestamp
            setZoom(math.zoomed(zoom, to: zoom.scale * (delta > 0 ? 1.25 : 1 / 1.25), around: anchor(event)))
            return
        }
        if math.isFit(zoom) {
            guard navigationEnabled else { return }
            // Still the wheel that zoomed out to fit: wait for a pause before changing photos.
            if event.timestamp - lastZoomInput < Self.navigationPause {
                lastZoomInput = event.timestamp
                return
            }
            onCommand?(delta < 0 ? .next : .previous)
        } else {
            lastZoomInput = event.timestamp
            let factor = delta > 0 ? 1.25 : 1 / 1.25
            setZoom(math.zoomed(zoom, to: zoom.scale * factor, around: anchor(event)))
        }
    }

    /// How long the wheel must rest after zooming before it changes photos.
    static let navigationPause = 0.4

    override func magnify(with event: NSEvent) {
        guard let math else { return }
        lastZoomInput = event.timestamp
        setZoom(math.zoomed(zoom, to: zoom.scale * (1 + event.magnification), around: anchor(event)))
    }

    override func smartMagnify(with event: NSEvent) {
        toggleZoom(at: anchor(event))
    }

    override func resetCursorRects() {
        if fitted {
            // No previous/next pointers where navigation is off (the crop tool's toolbar sits over the band).
            if image != nil, navigationEnabled {
                addCursorRect(bandRect(.previous), cursor: Cursors.previous)
                addCursorRect(bandRect(.next), cursor: Cursors.next)
            }
        } else {
            addCursorRect(imageArea, cursor: .openHand)
        }
    }
}

/// The bottom band's pointers: a chevron on a small graphite disc, readable on any photo.
@MainActor
enum Cursors {
    static let previous = chevron("chevron.left")
    static let next = chevron("chevron.right")

    private static func chevron(_ symbol: String) -> NSCursor {
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size, flipped: false) { rect in
            let disc = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
            NSColor(hex: DesignTokens.Colour.graphiteSurface).withAlphaComponent(0.92).setFill()
            disc.fill()
            NSColor(hex: DesignTokens.Colour.hairline).setStroke()
            disc.lineWidth = 1
            disc.stroke()
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
                .applying(.init(paletteColors: [NSColor(hex: DesignTokens.Colour.paperWhite)]))
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            {
                let g = glyph.size
                glyph.draw(
                    in: NSRect(
                        x: (rect.width - g.width) / 2, y: (rect.height - g.height) / 2, width: g.width, height: g.height
                    ))
            }
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 16, y: 16))
    }
}
