import AppKit
import RawBoyBrowseKit

/// Compare's window: like the viewer's (screen-filling, menu bar and Dock hidden while in front), with two to four
/// canvases: side by side, or two by two for four.
final class CompareWindowController: NSWindowController, NSWindowDelegate {
    let canvases: [ImageCanvasView]
    var onClose: (() -> Void)?
    private var isScreenFilling = true
    private let options: ViewerOptions
    let root: NSView
    /// The panes are a view in the host's window: no window of ours.
    let isEmbedded: Bool
    private var windowedFrame: NSRect?

    init(screen: NSScreen, count: Int, options: ViewerOptions) {
        self.options = options
        isEmbedded = options.viewerInHostWindow
        isScreenFilling = !options.viewerInHostWindow
        canvases = (0..<count).map { _ in ImageCanvasView(frame: .zero) }
        let root = ComparePanesView(panes: canvases)
        self.root = root
        if options.viewerInHostWindow {
            super.init(window: nil)
        } else {
            let window = ViewerWindow(
                contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
            window.backgroundColor = NSColor(hex: DesignTokens.Colour.inkBlack)
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.fullScreenNone, .managed]
            window.acceptsMouseMovedEvents = true
            window.contentView = root
            window.title = "Compare"
            super.init(window: window)
            window.delegate = self
            window.setFrame(screen.frame, display: false)
            observers = ScreenWatch.observe(window: window, hidesDock: options.hidesDockAndMenuBar) { [weak self] in
                self?.refit()
            }
        }
    }

    private var observers: [NSObjectProtocol] = []

    /// Our own window, or the host's the panes are in.
    override var window: NSWindow? {
        get { super.window ?? (isEmbedded ? root.window : nil) }
        set { super.window = newValue }
    }

    override func close() {
        guard isEmbedded else { return super.close() }
        windowWillClose(Notification(name: NSWindow.willCloseNotification))
    }

    /// The display went or changed: back onto one that exists.
    private func refit() {
        guard !isEmbedded, let window else { return }
        if ScreenWatch.refit(window, filling: isScreenFilling, windowedFrame: &windowedFrame) { updatePresentation() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func present() {
        if isEmbedded {
            window?.makeFirstResponder(canvases.first)
            return
        }
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvases.first)
        updatePresentation()
    }

    func toggleScreenFilling() {
        guard !isEmbedded, let window, let screen = window.screen ?? NSScreen.main else { return }
        isScreenFilling.toggle()
        if isScreenFilling {
            windowedFrame = window.frame
            window.styleMask = [.borderless]
            window.setFrame(screen.frame, display: true)
        } else {
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.setFrame(windowedFrame ?? screen.visibleFrame.insetBy(dx: 80, dy: 60), display: true)
        }
        updatePresentation()
    }

    private func updatePresentation() {
        guard options.hidesDockAndMenuBar, !isEmbedded else { return }
        let hide = isScreenFilling && (window?.isKeyWindow ?? false)
        let asked: NSApplication.PresentationOptions = hide ? [.hideDock, .hideMenuBar] : []
        if NSApp.presentationOptions != asked { NSApp.presentationOptions = asked }
    }

    func windowDidBecomeKey(_ notification: Notification) { updatePresentation() }
    func windowDidResignKey(_ notification: Notification) { updatePresentation() }

    func windowWillClose(_ notification: Notification) {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if options.hidesDockAndMenuBar && !isEmbedded { NSApp.presentationOptions = [] }
        onClose?()
    }
}

/// The panes, with a hairline between them.
final class ComparePanesView: NSView {
    let panes: [ImageCanvasView]

    init(panes: [ImageCanvasView]) {
        self.panes = panes
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(hex: DesignTokens.Colour.hairline).cgColor
        panes.forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        let gap = 2.0
        let columns = panes.count == 4 ? 2 : panes.count
        let rows = panes.count == 4 ? 2 : 1
        let w = (bounds.width - gap * Double(columns - 1)) / Double(columns)
        let h = (bounds.height - gap * Double(rows - 1)) / Double(rows)
        for (i, pane) in panes.enumerated() {
            let column = i % columns
            let row = i / columns
            pane.frame = CGRect(
                x: Double(column) * (w + gap), y: bounds.height - Double(row + 1) * h - Double(row) * gap, width: w,
                height: h)
        }
    }
}
