import AppKit
import RawBoyBrowseKit

/// Viewer keys by physical key (`keyCode`), not by the character typed, so they work on any keyboard layout
/// (RawBoy's `shortcutKey()` does the same on the web). See PLAN.md §2 for the full table.
enum ViewerKeys {
    // Virtual key codes of the ANSI layout's positions.
    private static let x: UInt16 = 7
    private static let s: UInt16 = 1
    private static let c: UInt16 = 8
    private static let r: UInt16 = 15
    private static let leftBracket: UInt16 = 33
    private static let rightBracket: UInt16 = 30
    private static let u: UInt16 = 32
    private static let p: UInt16 = 35
    /// The digit row: 0–5.
    static let digits: [UInt16: Int] = [29: 0, 18: 1, 19: 2, 20: 3, 21: 4, 23: 5]
    private static let f: UInt16 = 3
    private static let g: UInt16 = 5
    private static let z: UInt16 = 6
    private static let b: UInt16 = 11
    private static let e: UInt16 = 14
    private static let i: UInt16 = 34
    private static let j: UInt16 = 38
    private static let m: UInt16 = 46
    private static let tab: UInt16 = 48
    private static let returnKey: UInt16 = 36
    private static let enter: UInt16 = 76
    private static let space: UInt16 = 49
    private static let delete: UInt16 = 51
    private static let escape: UInt16 = 53
    private static let home: UInt16 = 115
    private static let end: UInt16 = 119
    private static let left: UInt16 = 123
    private static let right: UInt16 = 124
    private static let down: UInt16 = 125
    private static let up: UInt16 = 126

    static func command(for event: NSEvent) -> ViewerCommand? {
        // Leave ⌘ and ⌃ shortcuts to the menus (⌘⌫ will be Move to Trash).
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return nil }
        if let stars = digits[event.keyCode] { return .setStars(stars) }
        switch event.keyCode {
        case leftBracket: return .rotate(clockwise: false)
        case rightBracket: return .rotate(clockwise: true)
        case r: return .toggleRealPreview
        case s: return .toggleSlideshow
        case c: return .compare
        case p: return .toggleFlag(.pick)
        case x: return .toggleFlag(.reject)
        case u: return .unflag
        case right, down, space: return .next
        case left, up, delete: return .previous
        case home: return .first
        case end: return .last
        case z: return .toggleZoom
        case escape: return .dismiss
        case g, returnKey, enter: return .close
        case f: return .toggleFullScreen
        case i: return .togglePanel(.right)
        case j: return .toggleClipping
        case m: return .togglePanel(.left)
        case b: return .togglePanel(.top)
        case tab: return .toggleChrome
        case e: return .openInEditor
        default: return nil
        }
    }
}
