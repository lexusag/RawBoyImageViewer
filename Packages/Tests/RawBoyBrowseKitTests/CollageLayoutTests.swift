import RawBoyBrowseKit
import Testing

struct CollageLayoutTests {
    let square = CollageCanvas(width: 1000, height: 1000)

    @Test func canvasSizesAreClamped() {
        let c = CollageCanvas(width: 10, height: 99999)
        #expect(c.width == CollageCanvas.minSide && c.height == CollageCanvas.maxSide)
        #expect(CollageCanvas.presets[0].canvas.presetName == "Square 1:1")
        #expect(CollageCanvas(width: 1234, height: 999).presetName == nil)
    }

    @Test func arrangesLandscapePhotosInRows() {
        let l = CollageLayout.arranged(ids: ["a", "b"], aspects: [1.5, 1.5], canvas: square)
        // Two landscape photos on a square: stacked (1000 x 500 cells), not side by side (500 x 1000).
        #expect(
            l.items.map(\.frame) == [
                Rect2D(x: 0, y: 0, width: 1000, height: 500), Rect2D(x: 0, y: 500, width: 1000, height: 500),
            ])
    }

    @Test func arrangesNarrowPhotosInColumns() {
        let l = CollageLayout.arranged(ids: ["a", "b", "c"], aspects: [0.4, 0.4, 0.4], canvas: square)
        #expect(l.items.count == 3)
        #expect(l.items.allSatisfy { $0.frame.height == 1000 && abs($0.frame.width - 1000.0 / 3) < 1e-9 })
    }

    @Test func oddCountsFillTheCanvas() {
        let l = CollageLayout.arranged(
            ids: ["a", "b", "c", "d", "e"], aspects: Array(repeating: 1, count: 5), canvas: square)
        let area = l.items.map { $0.frame.width * $0.frame.height }.reduce(0, +)
        #expect(abs(area - 1_000_000) < 1e-6)
    }

    @Test func gapShrinksEachPhoto() {
        var l = CollageLayout(canvas: square, gap: 20)
        l.items = [CollageItem(id: "a", frame: Rect2D(x: 0, y: 0, width: 500, height: 500))]
        #expect(l.drawnFrame(l.items[0].frame) == Rect2D(x: 10, y: 10, width: 480, height: 480))
    }

    @Test func retargetKeepsRelativePlace() {
        var l = CollageLayout(canvas: square)
        l.items = [CollageItem(id: "a", frame: Rect2D(x: 100, y: 200, width: 500, height: 400))]
        l.retarget(to: CollageCanvas(width: 2000, height: 500))
        #expect(l.items[0].frame == Rect2D(x: 200, y: 100, width: 1000, height: 200))
    }

    @Test func hitPrefersHandlesThenTopmost() {
        var l = CollageLayout(canvas: square)
        l.items = [
            CollageItem(id: "a", frame: Rect2D(x: 0, y: 0, width: 600, height: 600)),
            CollageItem(id: "b", frame: Rect2D(x: 400, y: 400, width: 500, height: 500)),
        ]
        #expect(l.hit(at: Point2D(x: 500, y: 500), selected: nil, handleRadius: 10) == .body("b"))
        #expect(l.hit(at: Point2D(x: 100, y: 100), selected: nil, handleRadius: 10) == .body("a"))
        #expect(l.hit(at: Point2D(x: 600, y: 600), selected: "a", handleRadius: 10) == .handle("a", .bottomRight))
        #expect(l.hit(at: Point2D(x: 990, y: 990), selected: "a", handleRadius: 10) == nil)
        l.bringToFront("a")
        #expect(l.hit(at: Point2D(x: 500, y: 500), selected: nil, handleRadius: 10) == .body("a"))
    }

    @Test func moveStaysInsideAndSnaps() {
        var l = CollageLayout(canvas: square)
        let a = Rect2D(x: 100, y: 100, width: 300, height: 300)
        l.items = [
            CollageItem(id: "a", frame: a),
            CollageItem(id: "b", frame: Rect2D(x: 600, y: 600, width: 200, height: 200)),
        ]
        #expect(l.moved(a, dx: -500, dy: 2000, excluding: "a") == Rect2D(x: 0, y: 700, width: 300, height: 300))
        // Left edge 5 px short of b's left edge: snaps onto it.
        #expect(l.moved(a, dx: 495, dy: 0, excluding: "a").x == 600)
        // Far from every line: unchanged.
        #expect(l.moved(a, dx: 50, dy: 50, excluding: "a") == Rect2D(x: 150, y: 150, width: 300, height: 300))
    }

    @Test func resizeKeepsTheOppositeEdgeAndAMinimum() {
        var l = CollageLayout(canvas: square)
        let a = Rect2D(x: 100, y: 100, width: 300, height: 300)
        l.items = [CollageItem(id: "a", frame: a)]
        #expect(
            l.resized(a, handle: .bottomRight, dx: 150, dy: 70, excluding: "a")
                == Rect2D(x: 100, y: 100, width: 450, height: 370))
        let shrunk = l.resized(a, handle: .topLeft, dx: 900, dy: 900, excluding: "a")
        #expect(shrunk.maxX == 400 && shrunk.maxY == 400 && shrunk.width == CollageLayout.minFrame)
        #expect(l.resized(a, handle: .right, dx: 5000, dy: 0, excluding: "a").maxX == 1000)
    }

    @Test func coverFillsTheFrame() {
        let frame = Rect2D(x: 0, y: 0, width: 100, height: 100)
        let wide = CollageLayout.coverRect(image: Size2D(width: 400, height: 200), in: frame)
        #expect(wide == Rect2D(x: -50, y: 0, width: 200, height: 100))
        let tall = CollageLayout.coverRect(image: Size2D(width: 100, height: 300), in: frame)
        #expect(tall == Rect2D(x: 0, y: -100, width: 100, height: 300))
    }
}
