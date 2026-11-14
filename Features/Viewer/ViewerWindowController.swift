import AppKit
import RawBoyBrowseKit

/// A window that can be key without a title bar.
final class ViewerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The viewer's window. Screen-filling by default: a borderless window over the whole screen, with the menu bar and
/// Dock hidden while it is the key window. Native macOS full screen isn't used, because there the menu bar comes down
/// when the pointer reaches the top edge and the Dock comes up at the bottom, where the viewer's own edge controls go
/// (PLAN.md §2).
final class ViewerWindowController: NSWindowController, NSWindowDelegate {
    let canvas = ImageCanvasView(frame: .zero)
    var onClose: (() -> Void)?
    private(set) var isScreenFilling = true
    private var windowedFrame: NSRect?

    init(screen: NSScreen) {
        let window = ViewerWindow(
            contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
        window.backgroundColor = NSColor(hex: DesignTokens.Colour.inkBlack)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenNone, .managed]
        window.contentView = canvas
        window.title = "RawBoy Viewer"
        super.init(window: window)
        window.delegate = self
        window.setFrame(screen.frame, display: false)
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

    /// Screen-filling ↔ an ordinary titled window.
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
            window.titleVisibility = .visible
            window.setFrame(windowedFrame ?? screen.visibleFrame.insetBy(dx: 80, dy: 60), display: true)
        }
        window.makeFirstResponder(canvas)
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

    func windowDidBecomeKey(_ notification: Notification) { updatePresentation() }
    func windowDidResignKey(_ notification: Notification) { updatePresentation() }

    func windowDidChangeScreen(_ notification: Notification) {
        guard isScreenFilling, let window, let screen = window.screen else { return }
        window.setFrame(screen.frame, display: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.presentationOptions = []
        onClose?()
    }
}
