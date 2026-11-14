import AppKit
import RawBoyBrowseKit

/// A window that can be key without a title bar.
final class ViewerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The viewer's window and its edge panels. Screen-filling by default: a borderless window over the whole screen,
/// with the menu bar and Dock hidden while it is the key window. Native macOS full screen isn't used, because there
/// the menu bar comes down when the pointer reaches the top edge and the Dock comes up at the bottom, where the
/// viewer's own edge controls are (PLAN.md §2).
final class ViewerWindowController: NSWindowController, NSWindowDelegate {
    let root: ViewerRootView
    var canvas: ImageCanvasView { root.canvas }
    var onClose: (() -> Void)?
    private let model: ViewerModel
    private(set) var isScreenFilling = true
    private var windowedFrame: NSRect?

    private var zones: EdgeZones
    private var pointer: Point2D?
    private var deadline: DispatchWorkItem?
    private var moveMonitor: Any?
    private var wheelMonitor: Any?

    private static let pinnedKey = "viewer.pinnedEdges"

    init(screen: NSScreen, model: ViewerModel) {
        self.model = model
        let pinned = Set((UserDefaults.standard.stringArray(forKey: Self.pinnedKey) ?? []).compactMap(PanelEdge.init))
        zones = EdgeZones(pinned: pinned)
        root = ViewerRootView(model: model)
        let window = ViewerWindow(
            contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        window.backgroundColor = NSColor(hex: DesignTokens.Colour.inkBlack)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenNone, .managed]
        window.acceptsMouseMovedEvents = true
        window.contentView = root
        window.title = "RawBoy Viewer"
        super.init(window: window)
        window.delegate = self
        window.setFrame(screen.frame, display: false)
        root.onPointer = { [weak self] in self?.pointerMoved($0) }
        // Drags (mouse button down) don't reach mouseMoved; edges must still respond while dragging a photo.
        moveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            if event.window === self?.window { self?.root.report(event) }
            return event
        }
        // A mouse wheel turns vertically, the filmstrip scrolls sideways: over the filmstrip, up/down becomes
        // left/right (a trackpad already scrolls it sideways).
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            self?.filmstripWheel(event) ?? event
        }
        model.pinned = zones.pinned
        applyZones()
    }

    /// How far one wheel step moves the filmstrip, in its own lines (about a third of a thumbnail each).
    private static let filmstripWheelFactor = 4.0

    private func filmstripWheel(_ event: NSEvent) -> NSEvent {
        guard event.window === window, !event.hasPreciseScrollingDeltas, event.scrollingDeltaY != 0,
            event.scrollingDeltaX == 0, let strip = root.panels[.top], !strip.isHidden,
            strip.frame.contains(root.convert(event.locationInWindow, from: nil)),
            let cg = event.cgEvent?.copy()
        else { return event }
        let f = Self.filmstripWheelFactor
        let fields: [(CGEventField, CGEventField)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
            (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2),
            (.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2),
        ]
        for (vertical, horizontal) in fields {
            let value = cg.getDoubleValueField(vertical)
            cg.setDoubleValueField(horizontal, value: value * f)
            cg.setDoubleValueField(vertical, value: 0)
        }
        return NSEvent(cgEvent: cg) ?? event
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func present() {
        // Opened from Finder or a shell, the app may not be frontmost yet; the viewer must be the key window.
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
        updatePresentation()
    }

    // MARK: PanelEdge panels

    private func pointerMoved(_ p: Point2D?) {
        pointer = p
        updateZones()
    }

    private func updateZones() {
        let size = Size2D(width: root.bounds.width, height: root.bounds.height)
        zones.update(pointer: pointer, size: size, panels: root.panelRects, now: ProcessInfo.processInfo.systemUptime)
        applyZones()
    }

    private func applyZones() {
        root.apply(visible: zones.visible, reserved: zones.reservedEdges)
        if model.pinned != zones.pinned {
            model.pinned = zones.pinned
            UserDefaults.standard.set(zones.pinned.map(\.rawValue).sorted(), forKey: Self.pinnedKey)
        }
        // Wake up when a dwell or close delay ends, even if the pointer rests.
        deadline?.cancel()
        if let at = zones.nextDeadline {
            let work = DispatchWorkItem { [weak self] in self?.updateZones() }
            deadline = work
            let delay = max(at - ProcessInfo.processInfo.systemUptime, 0) + 0.005
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    func togglePanel(_ edge: PanelEdge) {
        zones.toggle(edge)
        applyZones()
    }

    func togglePin(_ edge: PanelEdge) {
        zones.togglePin(edge)
        applyZones()
        focusCanvas()
    }

    func toggleChrome() {
        zones.toggleChrome()
        applyZones()
    }

    /// Esc: closes showing panels; returns false when there were none (then Esc closes the viewer).
    func closePanels() -> Bool {
        let closed = zones.closeUnpinned()
        applyZones()
        return closed
    }

    /// Keys go to the canvas, also after a click in a panel.
    func focusCanvas() {
        window?.makeFirstResponder(canvas)
    }

    // MARK: Window

    /// Screen-filling ↔ an ordinary titled window.
    func toggleScreenFilling() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        isScreenFilling.toggle()
        model.isScreenFilling = isScreenFilling
        if isScreenFilling {
            windowedFrame = window.frame
            window.styleMask = [.borderless]
            window.setFrame(screen.frame, display: true)
        } else {
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .visible
            window.setFrame(windowedFrame ?? screen.visibleFrame.insetBy(dx: 80, dy: 60), display: true)
        }
        focusCanvas()
        updatePresentation()
    }

    func setTitle(_ title: String) {
        window?.title = title
    }

    /// The menu bar and Dock stay away only while a screen-filling viewer is the key window, so switching to another
    /// app brings them back.
    private func updatePresentation() {
        let hide = isScreenFilling && (window?.isKeyWindow ?? false)
        let options: NSApplication.PresentationOptions = hide ? [.hideDock, .hideMenuBar] : []
        if NSApp.presentationOptions != options {
            NSApp.presentationOptions = options
        }
        Trace.log(
            "presentation options: \(NSApp.currentSystemPresentationOptions.rawValue) (asked \(options.rawValue))")
    }

    func windowDidBecomeKey(_ notification: Notification) {
        Trace.log("viewer became key")
        updatePresentation()
    }

    func windowDidResignKey(_ notification: Notification) {
        Trace.log("viewer resigned key to \(NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "none")")
        updatePresentation()
        pointerMoved(nil)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard isScreenFilling, let window, let screen = window.screen else { return }
        window.setFrame(screen.frame, display: true)
    }

    func windowWillClose(_ notification: Notification) {
        deadline?.cancel()
        if let moveMonitor { NSEvent.removeMonitor(moveMonitor) }
        if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }
        moveMonitor = nil
        wheelMonitor = nil
        NSApp.presentationOptions = []
        onClose?()
    }
}
