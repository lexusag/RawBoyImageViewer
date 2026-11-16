import AppKit
import Foundation
import SwiftUI
import Testing

@testable import ViewerUI

@MainActor
struct TitleBarAndCopyTests {
    @Test func doubleClickActionFollowsTheSystemSetting() {
        #expect(TitleBarAction.from(setting: nil) == .zoom)
        #expect(TitleBarAction.from(setting: "Maximize") == .zoom)
        #expect(TitleBarAction.from(setting: "Minimize") == .minimize)
        #expect(TitleBarAction.from(setting: "None") == .nothing)
    }

    @Test func folderNameAndPath() {
        let url = URL(fileURLWithPath: "/Users/x/Pictures/Trip 2026/", isDirectory: true)
        #expect(FolderCopy.name(of: url) == "Trip 2026")
        #expect(FolderCopy.path(of: url) == "/Users/x/Pictures/Trip 2026")
        #expect(!FolderCopy.name(of: URL(fileURLWithPath: "/")).isEmpty)
    }
}

@MainActor
struct TitleBarZoomEventTests {
    private func click(_ count: Int, in window: NSWindow, at point: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
    }

    @Test func doubleClickOnTheBarZoomsTheWindowAndAnotherPutsItBack() throws {
        guard NSScreen.main != nil, TitleBarAction.current == .zoom else { return }
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: Color.clear.titleBarZoom())
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        window.contentView?.layoutSubtreeIfNeeded()
        let before = window.frame
        let point = NSPoint(x: 300, y: 200)
        let target = try #require(window.contentView?.hitTest(point))
        target.mouseDown(with: click(2, in: window, at: point))
        RunLoop.main.run(until: Date().addingTimeInterval(1))  // Zoom animates
        #expect(window.frame != before)
        target.mouseDown(with: click(2, in: window, at: point))
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        #expect(window.frame.size == before.size)
        window.orderOut(nil)
    }
}
