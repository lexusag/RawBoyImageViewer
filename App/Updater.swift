import Sparkle
import SwiftUI

/// Auto-update through Sparkle: the feed is appcast.xml in the repository, updates are signed with the owner's key
/// (SUPublicEDKey). Debug builds don't check by themselves (they'd offer the release over the build being worked on).
@MainActor
final class Updater {
    static let shared = Updater()

    #if DEBUG
        private static let startsAtLaunch = false
    #else
        private static let startsAtLaunch = true
    #endif

    let controller = SPUStandardUpdaterController(
        startingUpdater: startsAtLaunch, updaterDelegate: nil, userDriverDelegate: nil)
    private var started = startsAtLaunch

    func checkForUpdates() {
        if !started {
            try? controller.updater.start()
            started = true
        }
        controller.checkForUpdates(nil)
    }

    var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
