import RawBoyBrowseKit
import Testing

struct EdgeZonesTests {
    let size = Size2D(width: 1000, height: 600)
    let rightPanel = Rect2D(x: 668, y: 12, width: 320, height: 576)

    func p(_ x: Double, _ y: Double) -> Point2D { Point2D(x: x, y: y) }

    @Test func opensAfterTheDwellOnly() {
        var zones = EdgeZones()
        zones.update(pointer: p(998, 300), size: size, panels: [:], now: 0)
        #expect(zones.visible.isEmpty)
        #expect(zones.nextDeadline == 0.12)
        zones.update(pointer: p(998, 300), size: size, panels: [:], now: 0.13)
        #expect(zones.visible == [.right])
    }

    @Test func passingOverAnEdgeOpensNothing() {
        var zones = EdgeZones()
        zones.update(pointer: p(998, 300), size: size, panels: [:], now: 0)
        zones.update(pointer: p(900, 300), size: size, panels: [:], now: 0.05)
        zones.update(pointer: p(900, 300), size: size, panels: [:], now: 0.5)
        #expect(zones.visible.isEmpty)
    }

    @Test func staysOverThePanelAndItsGraceMargin() {
        var zones = opened(.right, at: p(998, 300))
        zones.update(pointer: p(700, 300), size: size, panels: [.right: rightPanel], now: 1)
        zones.update(pointer: p(650, 300), size: size, panels: [.right: rightPanel], now: 2)  // 18 pt outside
        #expect(zones.visible == [.right])
    }

    @Test func closesAfterTheDelayUnlessThePointerComesBack() {
        var zones = opened(.right, at: p(998, 300))
        zones.update(pointer: p(300, 300), size: size, panels: [.right: rightPanel], now: 1)
        #expect(zones.visible == [.right])
        #expect(zones.nextDeadline == 1.3)
        zones.update(pointer: p(700, 300), size: size, panels: [.right: rightPanel], now: 1.2)
        zones.update(pointer: p(700, 300), size: size, panels: [.right: rightPanel], now: 2)
        #expect(zones.visible == [.right])
        zones.update(pointer: p(300, 300), size: size, panels: [.right: rightPanel], now: 3)
        zones.update(pointer: p(300, 300), size: size, panels: [.right: rightPanel], now: 3.31)
        #expect(zones.visible.isEmpty)
    }

    @Test func cornersOpenNothing() {
        let zones = EdgeZones()
        #expect(zones.hotEdge(at: p(2, 2), in: size) == nil)
        #expect(zones.hotEdge(at: p(998, 590), in: size) == nil)
        #expect(zones.hotEdge(at: p(500, 3), in: size) == .top)
        #expect(zones.hotEdge(at: p(3, 300), in: size) == .left)
    }

    @Test func oneUnpinnedPanelAtATime() {
        var zones = opened(.right, at: p(998, 300))
        zones.toggle(.left)
        #expect(zones.visible == [.left])
    }

    @Test func keyHeldPanelIgnoresThePointer() {
        var zones = EdgeZones()
        zones.toggle(.right)
        zones.update(pointer: p(100, 300), size: size, panels: [.right: rightPanel], now: 10)
        #expect(zones.visible == [.right])
        zones.toggle(.right)
        #expect(zones.visible.isEmpty)
    }

    @Test func pinnedPanelsStayAndReserveRoom() {
        var zones = opened(.right, at: p(998, 300))
        zones.togglePin(.right)
        zones.update(pointer: p(100, 300), size: size, panels: [:], now: 10)
        zones.update(pointer: p(100, 300), size: size, panels: [:], now: 20)
        #expect(zones.visible == [.right])
        #expect(zones.reservedEdges == [.right])
        zones.toggle(.left)
        #expect(zones.visible == [.left, .right])
    }

    @Test func tabHidesEverythingThenBringsPinsBack() {
        var zones = EdgeZones(pinned: [.right])
        zones.toggle(.top)
        zones.toggleChrome()
        #expect(zones.visible.isEmpty)
        #expect(zones.reservedEdges.isEmpty)
        zones.toggleChrome()
        #expect(zones.visible == [.right])
    }

    @Test func escClosesUnpinnedPanelsFirst() {
        var zones = EdgeZones(pinned: [.right])
        zones.toggle(.left)
        let first = zones.closeUnpinned()
        let second = zones.closeUnpinned()
        #expect(first)
        #expect(!second)
        #expect(zones.visible == [.right])
    }

    @Test func leavingTheWindowClosesAfterTheDelay() {
        var zones = opened(.top, at: p(500, 2))
        zones.update(pointer: nil, size: size, panels: [:], now: 1)
        zones.update(pointer: nil, size: size, panels: [:], now: 1.4)
        #expect(zones.visible.isEmpty)
    }

    private func opened(_ edge: PanelEdge, at point: Point2D) -> EdgeZones {
        var zones = EdgeZones()
        zones.update(pointer: point, size: size, panels: [:], now: 0)
        zones.update(pointer: point, size: size, panels: [:], now: 0.2)
        #expect(zones.visible == [edge])
        return zones
    }
}

struct BottomBandTests {
    let area = Rect2D(x: 0, y: 0, width: 1000, height: 600)

    @Test func halvesOfTheBand() {
        #expect(BottomBand.height(of: area) == 72)
        #expect(BottomBand.command(at: Point2D(x: 100, y: 590), in: area) == .previous)
        #expect(BottomBand.command(at: Point2D(x: 900, y: 540), in: area) == .next)
        #expect(BottomBand.command(at: Point2D(x: 900, y: 520), in: area) == nil)
    }

    @Test func heightIsLimited() {
        #expect(BottomBand.height(of: Rect2D(x: 0, y: 0, width: 400, height: 200)) == 48)
        #expect(BottomBand.height(of: Rect2D(x: 0, y: 0, width: 4000, height: 3000)) == 160)
    }

    @Test func onlyInsideThePhotoArea() {
        let narrowed = Rect2D(x: 300, y: 0, width: 700, height: 600)
        #expect(BottomBand.command(at: Point2D(x: 100, y: 590), in: narrowed) == nil)
        #expect(BottomBand.command(at: Point2D(x: 400, y: 590), in: narrowed) == .previous)
    }
}
