/// The band along the bottom of the photo area: its left half goes to the previous photo, its right half to the next.
/// Only while the photo fits: zoomed in, dragging there pans (PLAN.md §2).
public enum BottomBand {
    /// The band's share of the photo area's height, kept between [minHeight] and [maxHeight] points.
    public static let fraction = 0.12
    public static let minHeight = 48.0
    public static let maxHeight = 160.0
    /// How long a held button waits before repeating, and then between steps, in seconds.
    public static let repeatDelay = 0.4
    public static let repeatInterval = 0.12

    public static func height(of area: Rect2D) -> Double {
        min(max(area.height * fraction, minHeight), maxHeight)
    }

    /// `.previous` or `.next` for [p] in the band of [area] (y down), else nil.
    public static func command(at p: Point2D, in area: Rect2D) -> ViewerCommand? {
        guard area.contains(p), p.y >= area.maxY - height(of: area) else { return nil }
        return p.x < area.x + area.width / 2 ? .previous : .next
    }
}
