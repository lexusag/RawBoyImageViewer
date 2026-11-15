import AppKit
import SwiftUI

/// Rubber-band selection for the grid and the list: press on empty space and drag. The rectangle lives in the
/// scrolled content's own coordinates, so it keeps its place while the view scrolls. A drag that starts on a
/// thumbnail or row is never ours: those carry the files out (`onDrag`), because this gesture sits *behind* the
/// cells and only receives what they leave.
@MainActor
@Observable
final class Marquee {
    /// The rectangle being drawn (content coordinates); nil when idle.
    var rect: CGRect?
    var position = ScrollPosition()
    /// The scroll view's height, so the content is never shorter than it (empty space below the cells is ours too).
    var viewportHeight = 0.0

    @ObservationIgnored var offset = 0.0
    @ObservationIgnored var maxOffset = 0.0
    @ObservationIgnored var frames: [String: CGRect] = [:]
    @ObservationIgnored private var dragging = false
    @ObservationIgnored private var moved = false
    @ObservationIgnored private var start = CGPoint.zero
    @ObservationIgnored private var pointer = CGPoint.zero
    @ObservationIgnored private var base: Set<String> = []
    @ObservationIgnored private var command = false
    @ObservationIgnored private var shift = false
    @ObservationIgnored private var timer: Timer?

    static let space = "marquee"
    /// Pointer within this many points of the top or bottom edge scrolls.
    static let edge = 40.0
    /// Points per tick at the very edge (30 ticks a second).
    static let maxSpeed = 22.0

    func changed(_ value: DragGesture.Value, browser: BrowserModel, focus: () -> Void) {
        if !dragging {
            dragging = true
            moved = false
            start = value.startLocation
            base = browser.selection
            let flags = NSEvent.modifierFlags
            command = flags.contains(.command)
            shift = flags.contains(.shift)
            focus()
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self, weak browser] _ in
                MainActor.assumeIsolated {
                    guard let self, let browser else { return }
                    self.tick(browser)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        pointer = value.location
        if !moved, hypot(pointer.x - start.x, pointer.y - start.y) < 3 { return }
        moved = true
        update(browser)
    }

    func ended(browser: BrowserModel) {
        timer?.invalidate()
        timer = nil
        // A click on empty space clears the selection, unless ⌘ or Shift is held.
        if dragging, !moved, !command, !shift { browser.clearSelection() }
        dragging = false
        moved = false
        rect = nil
    }

    private func update(_ browser: BrowserModel) {
        let r = CGRect(
            x: min(start.x, pointer.x), y: min(start.y, pointer.y),
            width: abs(pointer.x - start.x), height: abs(pointer.y - start.y))
        rect = r
        let hits = Set(frames.filter { $0.value.intersects(r) }.keys)
        browser.marqueeSelect(base: base, hits: hits, command: command, shift: shift)
    }

    /// Scrolls while the pointer rests near the top or bottom edge (no mouse events arrive then).
    private func tick(_ browser: BrowserModel) {
        guard dragging, moved, viewportHeight > 0 else { return }
        let y = pointer.y - offset
        var dy = 0.0
        if y < Self.edge {
            dy = -Self.maxSpeed * min((Self.edge - y) / Self.edge, 2)
        } else if y > viewportHeight - Self.edge {
            dy = Self.maxSpeed * min((y - (viewportHeight - Self.edge)) / Self.edge, 2)
        }
        guard dy != 0 else { return }
        let target = min(max(offset + dy, 0), maxOffset)
        guard target != offset else { return }
        pointer.y += target - offset
        offset = target
        position.scrollTo(y: target)
        update(browser)
    }
}

/// What the scroll view reports: where it is and how big it and its content are.
struct MarqueeScrollInfo: Equatable {
    var offset: Double
    var viewport: Double
    var content: Double
}

/// Each cell reports its frame (in the marquee's space), never the "Up a folder" tile.
private struct CellFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Makes this cell hittable by the marquee.
    func marqueeCell(_ id: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CellFramesKey.self, value: [id: proxy.frame(in: .named(Marquee.space))])
            })
    }

    /// The scrolled content: at least as tall as the viewport, with the drag surface behind it and the rectangle over it.
    func marqueeSurface(_ marquee: Marquee, browser: BrowserModel, focus: @escaping () -> Void) -> some View {
        frame(maxWidth: .infinity, minHeight: marquee.viewportHeight, alignment: .topLeading)
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(Marquee.space))
                            .onChanged { marquee.changed($0, browser: browser, focus: focus) }
                            .onEnded { _ in marquee.ended(browser: browser) }
                    )
            )
            .overlay {
                if let rect = marquee.rect {
                    Rectangle()
                        .fill(Theme.amber.opacity(0.12))
                        .overlay(Rectangle().strokeBorder(Theme.amber, lineWidth: 1))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: Marquee.space)
            .onPreferenceChange(CellFramesKey.self) { new in
                // While dragging, keep frames of cells scrolled out of the lazy stack (theirs don't change).
                if marquee.rect != nil { marquee.frames.merge(new) { $1 } } else { marquee.frames = new }
            }
    }

    /// Follows the scroll view so the marquee can scroll it and place the pointer.
    func marqueeScrolling(_ marquee: Marquee) -> some View {
        scrollPosition(Bindable(marquee).position)
            .onScrollGeometryChange(for: MarqueeScrollInfo.self) { geometry in
                MarqueeScrollInfo(
                    offset: geometry.contentOffset.y + geometry.contentInsets.top,
                    viewport: geometry.containerSize.height, content: geometry.contentSize.height)
            } action: { _, info in
                marquee.offset = info.offset
                marquee.viewportHeight = info.viewport
                marquee.maxOffset = max(info.content - info.viewport, 0)
            }
    }
}
