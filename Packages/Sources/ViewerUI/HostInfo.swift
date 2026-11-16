import Foundation

/// What the host app tells the screens about itself.
public enum HostInfo {
    /// "RawBoy Viewer 1.2.3 (45)": the first line of Help. Set once at launch.
    @MainActor public static var versionLine = "RawBoy Viewer"
    /// The app's updater (Settings shows its switch and "Check Now"), or nil when it has none.
    @MainActor public static var updater: (any AppUpdating)?
}

/// Updates the host app offers (Sparkle in RawBoy Viewer).
@MainActor
public protocol AppUpdating: AnyObject {
    var checksAutomatically: Bool { get set }
    func checkForUpdates()
}
