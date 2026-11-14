/// An EXIF orientation as what it does to the stored pixels: mirror left-right first (when [mirrored]), then turn
/// [quarterTurns] × 90° clockwise. Composing and inverting them is how a rotation is added on top of a photo's own
/// orientation.
public struct Orientation: Equatable, Hashable, Sendable {
    public let mirrored: Bool
    /// 0...3, clockwise.
    public let quarterTurns: Int

    public init(mirrored: Bool = false, quarterTurns: Int = 0) {
        self.mirrored = mirrored
        self.quarterTurns = ((quarterTurns % 4) + 4) % 4
    }

    public static let up = Orientation()

    /// EXIF/TIFF Orientation 1...8 (anything else: up).
    public init(exif: Int) {
        switch exif {
        case 2: self.init(mirrored: true)
        case 3: self.init(quarterTurns: 2)
        case 4: self.init(mirrored: true, quarterTurns: 2)
        case 5: self.init(mirrored: true, quarterTurns: 3)
        case 6: self.init(quarterTurns: 1)
        case 7: self.init(mirrored: true, quarterTurns: 1)
        case 8: self.init(quarterTurns: 3)
        default: self.init()
        }
    }

    public var exif: Int {
        switch (mirrored, quarterTurns) {
        case (false, 0): 1
        case (true, 0): 2
        case (false, 2): 3
        case (true, 2): 4
        case (true, 3): 5
        case (false, 1): 6
        case (true, 1): 7
        default: 8
        }
    }

    /// The photo's width and height swap.
    public var isQuarterTurned: Bool { quarterTurns % 2 == 1 }

    /// This, then [next].
    public func then(_ next: Orientation) -> Orientation {
        Orientation(
            mirrored: mirrored != next.mirrored,
            quarterTurns: next.mirrored ? next.quarterTurns - quarterTurns : next.quarterTurns + quarterTurns)
    }

    public var inverse: Orientation {
        mirrored ? self : Orientation(quarterTurns: -quarterTurns)
    }

    public static let clockwise = Orientation(quarterTurns: 1)
    public static let anticlockwise = Orientation(quarterTurns: 3)
}
