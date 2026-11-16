import AppKit

/// How one `AppModel` behaves in its host. The defaults are the standalone RawBoy Viewer's.
public struct ViewerOptions: Sendable {
    /// The screen-filling viewer and Compare hide the menu bar and Dock while one of them is the key window
    /// (`NSApp.presentationOptions`). A host with its own chrome turns this off.
    public var hidesDockAndMenuBar = true
    /// The viewer is a view the host places (`ViewerView`) instead of its own borderless window.
    public var viewerInHostWindow = false
    /// Quits the app (only the debug smoke scripts ask).
    public var quit: @MainActor @Sendable () -> Void = { NSApp.terminate(nil) }

    public init() {}
}
