import Testing

@testable import ViewerUI

@MainActor
struct ScrollBarTests {
    @Test func noThumbWhenEverythingFits() {
        let info = MarqueeScrollInfo(offset: 0, viewport: 800, content: 800)
        #expect(BrowserScrollBar.thumb(info, track: 800) == nil)
    }

    @Test func thumbLengthFollowsTheVisibleShare() throws {
        let info = MarqueeScrollInfo(offset: 0, viewport: 500, content: 2000)
        let thumb = try #require(BrowserScrollBar.thumb(info, track: 500))
        #expect(thumb.length == 125)
        #expect(thumb.top == 0)
    }

    @Test func thumbReachesTheBottomAtTheEnd() throws {
        let info = MarqueeScrollInfo(offset: 1500, viewport: 500, content: 2000)
        let thumb = try #require(BrowserScrollBar.thumb(info, track: 500))
        #expect(thumb.top + thumb.length == 500)
    }

    @Test func thumbNeverShrinksBelowTheMinimum() throws {
        let info = MarqueeScrollInfo(offset: 0, viewport: 500, content: 500_000)
        let thumb = try #require(BrowserScrollBar.thumb(info, track: 500))
        #expect(thumb.length == BrowserScrollBar.minThumb)
    }
}
