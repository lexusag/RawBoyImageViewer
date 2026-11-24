import Testing

@testable import ViewerUI

struct BrowserLayoutTests {
    @Test func wideWindowHonoursStoredWidths() {
        let layout = BrowserLayout.resolve(
            totalWidth: 1600, sidebarWidth: 248, previewWidth: 480, showPreview: true)
        #expect(layout.sidebarWidth == 248)
        #expect(layout.mainWidth == 1351)
        #expect(layout.previewWidth == 480)
        #expect(layout.contentWidth == 870)
        #expect(layout.sidebarWidth + 1 + layout.contentWidth + 1 + layout.previewWidth == 1600)
    }

    @Test func halfUltrawideClampsWidePreviewToKeepGridUsable() {
        let layout = BrowserLayout.resolve(
            totalWidth: 1150, sidebarWidth: 248, previewWidth: 760, showPreview: true)
        #expect(layout.sidebarWidth == 248)
        #expect(layout.mainWidth == 901)
        #expect(layout.contentWidth == BrowserLayout.minContentWidth)
        #expect(layout.previewWidth == 901 - 1 - BrowserLayout.minContentWidth)
        #expect(layout.livePreviewRange.upperBound == layout.previewWidth)
        #expect(layout.sidebarWidth + 1 + layout.contentWidth + 1 + layout.previewWidth == 1150)
    }

    @Test func minimumWindowClampsBothSidebarAndPreviewWithoutOverflow() {
        let layout = BrowserLayout.resolve(
            totalWidth: 900, sidebarWidth: 480, previewWidth: 760, showPreview: true)
        #expect(layout.sidebarWidth == 418)
        #expect(layout.mainWidth == 481)
        #expect(layout.previewWidth == BrowserLayout.previewRange.lowerBound)
        #expect(layout.contentWidth == BrowserLayout.minContentWidth)
        #expect(layout.sidebarWidth + 1 + layout.contentWidth + 1 + layout.previewWidth == 900)
    }

    @Test func previewOffGivesEntireMainAreaToContent() {
        let layout = BrowserLayout.resolve(
            totalWidth: 1280, sidebarWidth: 248, previewWidth: 760, showPreview: false)
        #expect(layout.sidebarWidth == 248)
        #expect(layout.mainWidth == 1031)
        #expect(layout.previewWidth == 0)
        #expect(layout.contentWidth == 1031)
    }

    @Test func veryNarrowAndZeroWidthsStayValid() {
        for width in [0.0, 200.0, 600.0] {
            let layout = BrowserLayout.resolve(
                totalWidth: width, sidebarWidth: 300, previewWidth: 500, showPreview: true)
            #expect(layout.sidebarWidth >= 0)
            #expect(layout.mainWidth >= 0)
            #expect(layout.previewWidth >= 0)
            #expect(layout.contentWidth >= 0)
            #expect(layout.liveSidebarRange.lowerBound <= layout.liveSidebarRange.upperBound)
            #expect(layout.livePreviewRange.lowerBound <= layout.livePreviewRange.upperBound)
            #expect(layout.sidebarWidth + layout.mainWidth <= width)
        }
    }
}
