import AppKit
import RawBoyBrowseKit

/// Compare's window: like the viewer's (screen-filling, menu bar and Dock hidden while in front), with two to four
/// canvases: side by side, or two by two for four.
final class CompareWindowController: NSWindowController, NSWindowDelegate {
    let canvases: [ImageCanvasView]
    var onClose: (() -> Void)?
    private var isScreenFilling = true
    private let options: ViewerOptions
    private var windowedFrame: NSRect?

    init(screen: NSScreen, count: Int, options: ViewerOptions) {
        self.options = options
        canvases = (0..<count).map { _ in ImageCanvasView(frame: .zero) }
        let root = ComparePanesView(panes: canvases)
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func present() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvases.first)
        updatePresentation()
    }

    func toggleScreenFilling() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
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
        guard options.hidesDockAndMenuBar else { return }
        let hide = isScreenFilling && (window?.isKeyWindow ?? false)
        let asked: NSApplication.PresentationOptions = hide ? [.hideDock, .hideMenuBar] : []
        if NSApp.presentationOptions != asked { NSApp.presentationOptions = asked }
    }

    func windowDidBecomeKey(_ notification: Notification) { updatePresentation() }
    func windowDidResignKey(_ notification: Notification) { updatePresentation() }

    func windowWillClose(_ notification: Notification) {
        if options.hidesDockAndMenuBar { NSApp.presentationOptions = [] }
        onClose?()
    }
}

/// The panes, with a hairline between them.
private final class ComparePanesView: NSView {
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
