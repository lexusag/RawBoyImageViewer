import Foundation
import Testing

@testable import ViewerUI

@MainActor
@Suite(.serialized)
struct PinnedRecentTests {
    @Test func pinsAreKeptInTheStoreUnderTheHostsPrefix() throws {
        let suiteName = "app.rawboy.viewer.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let old = ViewerSettings.store
        ViewerSettings.store = UserDefaultsSettings(defaults: defaults, prefix: "desktop.browse.")
        defer { ViewerSettings.store = old }

        let folder = URL(fileURLWithPath: "/Photos/Trip", isDirectory: true)
        let app = AppModel()
        #expect(!app.browser.isPinnedRecent(folder))
        app.browser.togglePinnedRecent(folder)
        #expect(app.browser.isPinnedRecent(folder))
        #expect(app.browser.recentListed == [folder.standardizedFileURL])
        #expect(defaults.stringArray(forKey: "desktop.browse.browser.pinnedRecentFolders") == ["/Photos/Trip"])

        // A new model reads it back; unpinning removes it.
        let again = AppModel()
        #expect(again.browser.isPinnedRecent(folder))
        again.browser.togglePinnedRecent(folder)
        #expect(again.browser.recentListed.isEmpty)
    }
}
