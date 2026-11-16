import Foundation
import Testing

@testable import RawBoyBrowseKit

struct RecentFoldersTests {
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/Photos/\(name)", isDirectory: true) }

    @Test func rememberingMovesAFolderToTheFrontAndKeepsEight() {
        var recent: [URL] = []
        for i in 1...10 { recent = RecentFolders.remembering(url("f\(i)"), in: recent) }
        #expect(recent.count == 8)
        #expect(recent.first == url("f10"))
        recent = RecentFolders.remembering(url("f5"), in: recent)
        #expect(recent.first == url("f5"))
        #expect(recent.filter { $0 == url("f5") }.count == 1)
        #expect(recent.count == 8)
    }

    @Test func togglingPinsLastAndUnpins() {
        var pinned = RecentFolders.toggling(url("a"), in: [])
        pinned = RecentFolders.toggling(url("b"), in: pinned)
        #expect(pinned == [url("a"), url("b")])
        pinned = RecentFolders.toggling(url("a"), in: pinned)
        #expect(pinned == [url("b")])
    }

    @Test func pinnedFoldersComeFirstAndSurviveTheLimit() {
        var recent: [URL] = []
        for i in 1...20 { recent = RecentFolders.remembering(url("f\(i)"), in: recent) }
        let pinned = [url("old")]  // not among the recents any more
        let listed = RecentFolders.listed(recent: recent, pinned: pinned)
        #expect(listed.first == url("old"))
        #expect(listed.count == 1 + RecentFolders.shown)
        #expect(listed[1] == url("f20"))
    }

    @Test func aPinnedFolderIsListedOnce() {
        let recent = [url("a"), url("b"), url("c")]
        let listed = RecentFolders.listed(recent: recent, pinned: [url("b")])
        #expect(listed == [url("b"), url("a"), url("c")])
    }
}
