import Foundation
import RawBoyBrowseKit
import ViewerImaging

/// What the host app gives the screens: its name and updater, and the three things that depend on what it is built
/// with (hand-off to RawBoy's apps, the raw preview, the settings store: see `ViewerSettings`). Set at launch, before
/// `AppModel.shared` is first used.
public enum ViewerHost {
    /// "RawBoy Viewer 1.2.3 (45)": the first line of Help. Set once at launch.
    @MainActor public static var versionLine = "RawBoy Viewer"
    /// The app's updater (Settings shows its switch and "Check Now"), or nil when it has none.
    @MainActor public static var updater: (any AppUpdating)?
    /// Opening photos in RawBoy's other apps (Open With and the `rawboy-desktop://` link in RawBoy Viewer).
    @MainActor public static var handOff: any PhotoHandOff = NoHandOff()
    /// What the R key shows for a raw (Core Image's RAW filter in RawBoy Viewer).
    nonisolated(unsafe) public static var realPreview: any RealPreviewProvider = CoreImageRealPreview()
}

/// Updates the host app offers (Sparkle in RawBoy Viewer).
@MainActor
public protocol AppUpdating: AnyObject {
    var checksAutomatically: Bool { get set }
    func checkForUpdates()
}

/// Where photos go to be edited or batch-developed: RawBoy Desktop (Pro, Auto) or another editor.
@MainActor
public protocol PhotoHandOff {
    /// The editor the E key opens when none is chosen in Settings: its name (for menus) and app (nil: the photo's
    /// default app).
    var editor: (name: String, url: URL?) { get }
    /// Whether "Send to RawBoy Auto" can be offered.
    var canSendToAuto: Bool { get }
    /// Adds [urls] (photos and folders) to Auto's batch as [how]; throws when it can't be opened.
    func sendToAuto(_ urls: [URL], as how: AutoImport) async throws
}

/// A host with nowhere to hand photos to.
struct NoHandOff: PhotoHandOff {
    var editor: (name: String, url: URL?) { ("default app", nil) }
    var canSendToAuto: Bool { false }
    func sendToAuto(_ urls: [URL], as how: AutoImport) async throws {}
}
