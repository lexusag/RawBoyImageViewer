import AppKit

/// Whether a menu (context menu, pop-up, menu bar) is open. Local key monitors see a key before the menu tracking it
/// does, so a monitor that takes Esc (back to the browser, clear the selection) would leave the menu open: they call
/// `isOpen` and let Esc through, which closes the menu alone.
@MainActor
enum MenuTracking {
    private(set) static var isOpen = false
    private static var observers: [NSObjectProtocol] = []

    /// Starts listening (idempotent).
    static func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { isOpen = true }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { isOpen = false }
            },
        ]
    }
}
