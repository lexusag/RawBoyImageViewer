import AppKit

/// An NSMenuItem that runs a closure (AppKit menus want a target and selector).
@MainActor
final class MenuAction: NSObject {
    private let run: () -> Void
    private init(_ run: @escaping () -> Void) { self.run = run }

    @objc private func fire() { run() }

    static func item(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
        item.target = action
        // The menu item holds its target weakly: keep the closure alive as long as the item.
        item.representedObject = action
        return item
    }
}
