import RawBoyBrowseKit
import Testing

struct ZoomMathTests {
    // A 6000 × 4000 photo in a 1200 × 800 pt window on a Retina screen.
    let math = ZoomMath(
        imageSize: Size2D(width: 6000, height: 4000), viewSize: Size2D(width: 1200, height: 800), backingScale: 2)

    @Test func fitAndOneToOne() {
        #expect(math.fitScale == 0.2)
        #expect(math.oneToOneScale == 0.5)
        #expect(math.devicePixelsPerImagePixel(ZoomState(scale: 0.5)) == 1)
    }

    @Test func smallImagesAreNotEnlarged() {
        let small = ZoomMath(
            imageSize: Size2D(width: 400, height: 300), viewSize: Size2D(width: 1200, height: 800), backingScale: 2)
        #expect(small.fitScale == 0.5)
        #expect(small.toggled(small.fit, around: Point2D(x: 100, y: 100)) == small.fit)
    }

    @Test func zoomKeepsThePointUnderTheAnchor() {
        let anchor = Point2D(x: 300, y: -200)
        let zoomed = math.zoomed(math.fit, to: 0.5, around: anchor)
        // The image point under the anchor at fit: (anchor - offset) / scale.
        let before = Point2D(x: anchor.x / 0.2, y: anchor.y / 0.2)
        let after = Point2D(
            x: (anchor.x - zoomed.offset.x) / zoomed.scale, y: (anchor.y - zoomed.offset.y) / zoomed.scale)
        #expect(abs(before.x - after.x) < 1e-9)
        #expect(abs(before.y - after.y) < 1e-9)
    }

    @Test func panStopsAtTheEdges() {
        let oneToOne = ZoomState(scale: 0.5)
        // At 1:1 the image is 3000 × 2000 pt: it can move 900 pt each way horizontally, 600 vertically.
        let panned = math.panned(oneToOne, by: Point2D(x: 5000, y: -5000))
        #expect(panned.offset == Point2D(x: 900, y: -600))
    }

    @Test func fitIsAlwaysCentred() {
        let state = math.clamped(ZoomState(scale: 0.2, offset: Point2D(x: 50, y: 50)))
        #expect(state.offset == .zero)
    }

    @Test func scaleIsLimited() {
        #expect(math.clamped(ZoomState(scale: 0.01)).scale == 0.2)
        #expect(math.clamped(ZoomState(scale: 100)).scale == 4)
    }

    @Test func toggleGoesBackToFit() {
        let zoomed = math.toggled(math.fit, around: Point2D(x: 10, y: 10))
        #expect(zoomed.scale == 0.5)
        #expect(math.toggled(zoomed, around: .zero) == math.fit)
    }
}

struct SharedZoomTests {
    @Test func roundTripsOnTheSamePhoto() {
        let math = ZoomMath(
            imageSize: Size2D(width: 6000, height: 4000), viewSize: Size2D(width: 1200, height: 800), backingScale: 2)
        let state = math.panned(ZoomState(scale: 0.5), by: Point2D(x: 300, y: -200))
        let back = math.state(math.shared(state))
        #expect(abs(back.scale - state.scale) < 1e-9)
        #expect(abs(back.offset.x - state.offset.x) < 1e-9)
        #expect(abs(back.offset.y - state.offset.y) < 1e-9)
    }

    @Test func anotherPhotoShowsTheSameSpot() {
        let a = ZoomMath(
            imageSize: Size2D(width: 6000, height: 4000), viewSize: Size2D(width: 600, height: 800), backingScale: 2)
        let b = ZoomMath(
            imageSize: Size2D(width: 3000, height: 2000), viewSize: Size2D(width: 600, height: 800), backingScale: 2)
        // A quarter of the way to the right of the centre, three times fit.
        let shared = SharedZoom(factor: 3, centre: Point2D(x: 0.25, y: 0))
        let state = b.state(shared)
        #expect(abs(state.scale - 3 * b.fitScale) < 1e-9)
        #expect(abs(b.shared(state).centre.x - 0.25) < 1e-9)
        #expect(a.state(.fit) == a.fit)
    }
}
