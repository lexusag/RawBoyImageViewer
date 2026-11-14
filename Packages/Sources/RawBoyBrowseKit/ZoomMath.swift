/// How a photo sits in the viewer: its scale and where its centre is.
public struct ZoomState: Equatable, Sendable {
    /// View points per image pixel.
    public var scale: Double
    /// The image centre's offset from the view centre, in points.
    public var offset: Point2D

    public init(scale: Double, offset: Point2D = .zero) {
        self.scale = scale
        self.offset = offset
    }
}

/// A zoom any photo can take on: how far past fit, and which point of the photo (as fractions of its size, from its
/// centre) is in the middle of the view. Compare passes it from pane to pane.
public struct SharedZoom: Equatable, Sendable {
    /// Scale over the fit scale (1 = fit).
    public var factor: Double
    public var centre: Point2D

    public init(factor: Double, centre: Point2D = .zero) {
        self.factor = factor
        self.centre = centre
    }

    public static let fit = SharedZoom(factor: 1)
}

/// Fit, 1:1, zooming at a point and panning limits for one image in one view.
///
/// Sizes are the full-resolution image in pixels and the view in points; points are relative to the view centre.
public struct ZoomMath: Equatable, Sendable {
    public let imageSize: Size2D
    public let viewSize: Size2D
    /// Device pixels per point (2 on Retina).
    public let backingScale: Double

    /// The largest zoom, as a multiple of 1:1.
    public static let maxZoom = 8.0

    public init(imageSize: Size2D, viewSize: Size2D, backingScale: Double) {
        self.imageSize = imageSize
        self.viewSize = viewSize
        self.backingScale = max(backingScale, 1)
    }

    /// One image pixel per device pixel.
    public var oneToOneScale: Double { 1 / backingScale }

    /// The whole image in the view, never enlarged past 1:1.
    public var fitScale: Double {
        guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
            return oneToOneScale
        }
        return min(viewSize.width / imageSize.width, viewSize.height / imageSize.height, oneToOneScale)
    }

    public var minScale: Double { fitScale }
    public var maxScale: Double { max(oneToOneScale * Self.maxZoom, fitScale) }

    public var fit: ZoomState { ZoomState(scale: fitScale) }

    public func isFit(_ state: ZoomState) -> Bool { abs(state.scale - fitScale) < fitScale * 1e-6 }

    /// The share of image pixels a view pixel shows: above 1 means the view needs more than a screen-size preview.
    public func devicePixelsPerImagePixel(_ state: ZoomState) -> Double { state.scale * backingScale }

    /// [state] with the scale in range and the image kept over the view: an edge never comes inside the view while
    /// the image is larger than it, and a smaller image stays centred.
    public func clamped(_ state: ZoomState) -> ZoomState {
        let scale = min(max(state.scale, minScale), maxScale)
        func axis(_ offset: Double, image: Double, view: Double) -> Double {
            let slack = (image * scale - view) / 2
            return slack <= 0 ? 0 : min(max(offset, -slack), slack)
        }
        return ZoomState(
            scale: scale,
            offset: Point2D(
                x: axis(state.offset.x, image: imageSize.width, view: viewSize.width),
                y: axis(state.offset.y, image: imageSize.height, view: viewSize.height)))
    }

    /// [state] zoomed to [scale], keeping the image point under [anchor] (relative to the view centre) in place.
    public func zoomed(_ state: ZoomState, to scale: Double, around anchor: Point2D) -> ZoomState {
        let target = min(max(scale, minScale), maxScale)
        let ratio = target / state.scale
        let offset = Point2D(
            x: anchor.x - (anchor.x - state.offset.x) * ratio,
            y: anchor.y - (anchor.y - state.offset.y) * ratio)
        return clamped(ZoomState(scale: target, offset: offset))
    }

    /// [state] moved by [delta] points.
    public func panned(_ state: ZoomState, by delta: Point2D) -> ZoomState {
        clamped(
            ZoomState(scale: state.scale, offset: Point2D(x: state.offset.x + delta.x, y: state.offset.y + delta.y)))
    }

    /// Fit ↔ 1:1, at [anchor] when zooming in. An image that fits at 1:1 already stays at fit.
    public func toggled(_ state: ZoomState, around anchor: Point2D) -> ZoomState {
        isFit(state) ? zoomed(state, to: oneToOneScale, around: anchor) : fit
    }

    /// [state] as a zoom other photos can take on.
    public func shared(_ state: ZoomState) -> SharedZoom {
        guard imageSize.width > 0, imageSize.height > 0, state.scale > 0 else { return .fit }
        return SharedZoom(
            factor: state.scale / fitScale,
            centre: Point2D(
                x: -state.offset.x / state.scale / imageSize.width,
                y: -state.offset.y / state.scale / imageSize.height))
    }

    /// [shared] on this photo, within its limits.
    public func state(_ shared: SharedZoom) -> ZoomState {
        let scale = shared.factor * fitScale
        return clamped(
            ZoomState(
                scale: scale,
                offset: Point2D(
                    x: -shared.centre.x * imageSize.width * scale, y: -shared.centre.y * imageSize.height * scale)))
    }
}
