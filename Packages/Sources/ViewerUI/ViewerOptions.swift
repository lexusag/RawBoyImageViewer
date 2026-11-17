import AppKit

/// How one `AppModel` behaves in its host. The defaults are the standalone RawBoy Viewer's.
public struct ViewerOptions: Sendable {
    /// The screen-filling viewer and Compare hide the menu bar and Dock while one of them is the key window
    /// (`NSApp.presentationOptions`). A host with its own chrome turns this off.
    public var hidesDockAndMenuBar = true
    /// The viewer and Compare are views the host places (`ViewerView`, `CompareView`) instead of their own borderless
    /// windows. Changeable while the model lives: it applies to the next viewer or Compare that opens (`AppModel.options`).
    public var viewerInHostWindow = false
    /// Their own windows open on the display the host's window is on, not the one under the pointer.
    public var opensOnHostScreen = false
    /// Extra space above the browser's toolbar, in points, for a host that draws its own controls over the top of the
    /// window (RawBoy Desktop's mode switch). 0 keeps the standalone layout.
    public var toolbarTopInset: CGFloat = 0
    /// Quits the app (only the debug smoke scripts ask).
    public var quit: @MainActor @Sendable () -> Void = { NSApp.terminate(nil) }

    public init() {}
}

/// The options a model's sessions read each time they open something, so a host can change them at runtime.
@MainActor
final class ViewerOptionsBox {
    var value: ViewerOptions
    init(_ value: ViewerOptions) { self.value = value }
}
