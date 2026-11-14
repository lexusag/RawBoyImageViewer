/// Small value types, so RawBoyBrowseKit needs no CoreGraphics and builds on any platform.
public struct Point2D: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point2D(x: 0, y: 0)
}

public struct Size2D: Equatable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = Size2D(width: 0, height: 0)
}

/// A rectangle with y growing downwards (top-left origin), as the viewer's edge logic uses everywhere.
public struct Rect2D: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public func contains(_ p: Point2D) -> Bool { p.x >= x && p.x <= maxX && p.y >= y && p.y <= maxY }

    /// Grown by [d] on every side (shrunk when negative).
    public func expanded(by d: Double) -> Rect2D {
        Rect2D(x: x - d, y: y - d, width: width + 2 * d, height: height + 2 * d)
    }
}
