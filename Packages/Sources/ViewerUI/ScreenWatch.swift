import AppKit

/// Where a screen-filling window goes when displays come and go, and when the menu bar and Dock must come back.
enum ScreenWatch {
    /// The index of the display in [screens] that [window] overlaps most; nil when it overlaps none (its display is
    /// gone). Pure, so it is tested without displays.
    static func screenIndex(for window: CGRect, among screens: [CGRect]) -> Int? {
        var best: (index: Int, area: Double)?
        for (i, screen) in screens.enumerated() {
            let overlap = window.intersection(screen)
            let area = overlap.isNull ? 0 : Double(overlap.width * overlap.height)
            if area > 0, area > (best?.area ?? 0) { best = (i, area) }
        }
        return best?.index
    }

    /// Calls [refit] when the displays change, and puts the menu bar and Dock back when the app resigns or quits.
    @MainActor
    static func observe(window: NSWindow, hidesDock: Bool, refit: @escaping @MainActor () -> Void)
        -> [NSObjectProtocol]
    {
        let center = NotificationCenter.default
        var tokens: [NSObjectProtocol] = []
        tokens.append(
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main)
            {
                _ in MainActor.assumeIsolated { refit() }
            })
        if hidesDock {
            // The window resigns key with the app, which restores them; this is for a window that stays key (the app
            // in the background with it, or quitting).
            for name in [NSApplication.didResignActiveNotification, NSApplication.willTerminateNotification] {
                tokens.append(
                    center.addObserver(forName: name, object: nil, queue: .main) { _ in
                        MainActor.assumeIsolated { NSApp.presentationOptions = [] }
                    })
            }
        }
        return tokens
    }

    /// Puts [window] on a display that exists (the one it is on, else the main one): filling it, or, as an ordinary
    /// window, inside its visible area.
    @MainActor
    static func refit(_ window: NSWindow, filling: Bool, windowedFrame: inout NSRect?) {
        let screens = NSScreen.screens
        let index = screenIndex(for: window.frame, among: screens.map(\.frame))
        guard let screen = index.map({ screens[$0] }) ?? NSScreen.main ?? screens.first else { return }
        if filling {
            window.setFrame(screen.frame, display: true)
        } else if index == nil {
            window.setFrame(screen.visibleFrame.insetBy(dx: 80, dy: 60), display: true)
        }
    }
}
