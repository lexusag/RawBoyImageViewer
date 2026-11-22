import Foundation

/// The output size of a collage, in pixels.
public struct CollageCanvas: Equatable, Hashable, Sendable {
    public static let minSide = 200
    public static let maxSide = 8000

    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = min(Self.maxSide, max(Self.minSide, width))
        self.height = min(Self.maxSide, max(Self.minSide, height))
    }

    public var size: Size2D { Size2D(width: Double(width), height: Double(height)) }
    public var aspect: Double { Double(width) / Double(height) }

    /// What the size sheet offers besides Custom.
    public static let presets: [(name: String, canvas: CollageCanvas)] = [
        ("Square 1:1", CollageCanvas(width: 1080, height: 1080)),
        ("Portrait 4:5", CollageCanvas(width: 1080, height: 1350)),
        ("Portrait 3:4", CollageCanvas(width: 1440, height: 1920)),
        ("Portrait 2:3", CollageCanvas(width: 1080, height: 1620)),
        ("Story 9:16", CollageCanvas(width: 1080, height: 1920)),
        ("Landscape 4:3", CollageCanvas(width: 1440, height: 1080)),
        ("Landscape 3:2", CollageCanvas(width: 1620, height: 1080)),
        ("Landscape 1.91:1", CollageCanvas(width: 1080, height: 566)),
    ]

    /// The preset's name for this size, or nil for a custom one.
    public var presetName: String? { Self.presets.first { $0.canvas == self }?.name }
}

/// One photo on the collage: [frame] is in canvas pixels, y down. The photo fills the frame (cropped at the edges,
/// never stretched).
public struct CollageItem: Equatable, Identifiable, Sendable {
    public let id: String
    public var frame: Rect2D
    /// Which part of the photo shows when it overflows the frame: 0...1 on each axis, (0.5, 0.5) = centred, (0, 0) =
    /// the top left edge of the photo against the frame's.
    public var focus: Point2D

    public init(id: String, frame: Rect2D, focus: Point2D = CollageItem.centred) {
        self.id = id
        self.frame = frame
        self.focus = focus
    }

    public static let centred = Point2D(x: 0.5, y: 0.5)
}

/// Where a pointer press on the collage lands.
public enum CollageHit: Equatable, Sendable {
    case body(String)
    case handle(String, CollageHandle)
}

/// The eight resize handles of a frame.
public enum CollageHandle: CaseIterable, Equatable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    /// The handle's position on [r].
    public func point(on r: Rect2D) -> Point2D {
        let x = movesLeft ? r.x : (movesRight ? r.maxX : r.x + r.width / 2)
        let y = movesTop ? r.y : (movesBottom ? r.maxY : r.y + r.height / 2)
        return Point2D(x: x, y: y)
    }
}

/// A collage: photos placed on a canvas of a chosen size over a background colour. Items are in drawing order (the
/// last one is on top). Pure value logic, so it is tested without a window.
public struct CollageLayout: Equatable, Sendable {
    /// Smallest width or height a frame can be dragged to, in canvas pixels.
    public static let minFrame: Double = 60
    /// Nearest edge or centre line a drag snaps to, in canvas pixels.
    public static let snapDistance: Double = 12

    public var canvas: CollageCanvas
    public var items: [CollageItem]
    /// The space between photos, in canvas pixels: every photo is drawn this much smaller (half on each side), so
    /// photos that touch are one gap apart and the canvas edge gets half a gap.
    public var gap: Double
    /// The background (the frame colour) as 0xRRGGBB.
    public var background: UInt32

    public init(canvas: CollageCanvas, items: [CollageItem] = [], gap: Double = 24, background: UInt32 = 0xFFFFFF) {
        self.canvas = canvas
        self.items = items
        self.gap = gap
        self.background = background
    }

    /// A layout of [ids] (their pixel aspects, width / height, in [aspects]) tiled over [canvas].
    public static func arranged(ids: [String], aspects: [Double], canvas: CollageCanvas, gap: Double = 24)
        -> CollageLayout
    {
        var layout = CollageLayout(canvas: canvas, gap: gap)
        layout.items = ids.map { CollageItem(id: $0, frame: .init(x: 0, y: 0, width: 1, height: 1)) }
        layout.arrange(aspects: aspects)
        return layout
    }

    /// Tiles the photos in rows of near-equal counts, choosing the row count whose cells are closest to the photos'
    /// own shapes (so little is cropped). Order is kept; frames are replaced.
    public mutating func arrange(aspects: [Double]) {
        let n = items.count
        guard n > 0 else { return }
        let w = canvas.size.width
        let h = canvas.size.height
        let mean = aspects.isEmpty ? 1 : aspects.reduce(0, +) / Double(aspects.count)
        var bestRows = 1
        var bestScore = Double.infinity
        for rows in 1...n {
            let cols = Int((Double(n) / Double(rows)).rounded(.up))
            let cellAspect = (w / Double(cols)) / (h / Double(rows))
            let score = abs(log(cellAspect / max(0.05, mean)))
            if score < bestScore - 1e-9 {
                bestScore = score
                bestRows = rows
            }
        }
        // Rows hold n / rows photos, the first n % rows rows one more; each row's cells share its width.
        let base = n / bestRows
        let extra = n % bestRows
        var index = 0
        let rowHeight = h / Double(bestRows)
        for row in 0..<bestRows {
            let count = base + (row < extra ? 1 : 0)
            let cellWidth = w / Double(count)
            for col in 0..<count {
                items[index].frame = Rect2D(
                    x: Double(col) * cellWidth, y: Double(row) * rowHeight, width: cellWidth, height: rowHeight)
                index += 1
            }
        }
    }

    /// The frame [id] is drawn in: its frame shrunk by half the gap.
    public func drawnFrame(_ frame: Rect2D) -> Rect2D {
        let inset = min(gap / 2, min(frame.width, frame.height) / 4)
        return frame.expanded(by: -inset)
    }

    /// The same layout on another canvas: frames keep their place and size relative to it.
    public mutating func retarget(to new: CollageCanvas) {
        guard new != canvas else { return }
        let sx = Double(new.width) / Double(canvas.width)
        let sy = Double(new.height) / Double(canvas.height)
        for i in items.indices {
            let f = items[i].frame
            items[i].frame = Rect2D(x: f.x * sx, y: f.y * sy, width: f.width * sx, height: f.height * sy)
        }
        canvas = new
    }

    public func item(_ id: String) -> CollageItem? { items.first { $0.id == id } }

    /// Takes a photo out of the collage.
    public mutating func remove(_ id: String) { items.removeAll { $0.id == id } }

    /// Puts [id] on top of the others.
    public mutating func bringToFront(_ id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }), i != items.count - 1 else { return }
        items.append(items.remove(at: i))
    }

    // MARK: Pointer

    /// What a press at [point] (canvas pixels) lands on: a handle of [selected] first (within [handleRadius]), then the
    /// topmost frame under it.
    public func hit(at point: Point2D, selected: String?, handleRadius: Double) -> CollageHit? {
        if let selected, let item = item(selected) {
            for handle in CollageHandle.allCases {
                let p = handle.point(on: item.frame)
                if abs(p.x - point.x) <= handleRadius && abs(p.y - point.y) <= handleRadius {
                    return .handle(selected, handle)
                }
            }
        }
        for item in items.reversed() where item.frame.contains(point) { return .body(item.id) }
        return nil
    }

    // MARK: Editing

    /// [start] moved by [dx], [dy], kept inside the canvas and snapped to the canvas edges and centre and to the
    /// other photos' edges.
    public func moved(_ start: Rect2D, dx: Double, dy: Double, excluding id: String) -> Rect2D {
        let others = items.filter { $0.id != id }.map(\.frame)
        let w = canvas.size.width
        let h = canvas.size.height
        var x = min(max(0, start.x + dx), max(0, w - start.width))
        var y = min(max(0, start.y + dy), max(0, h - start.height))
        let xTargets: [Double] = [0, w / 2, w] + others.flatMap { [$0.x, $0.maxX, $0.x + $0.width / 2] as [Double] }
        let yTargets: [Double] = [0, h / 2, h] + others.flatMap { [$0.y, $0.maxY, $0.y + $0.height / 2] as [Double] }
        x += Self.snapOffset(of: [x, x + start.width / 2, x + start.width], to: xTargets)
        y += Self.snapOffset(of: [y, y + start.height / 2, y + start.height], to: yTargets)
        x = min(max(0, x), max(0, w - start.width))
        y = min(max(0, y), max(0, h - start.height))
        return Rect2D(x: x, y: y, width: start.width, height: start.height)
    }

    /// [start] with [handle] dragged by [dx], [dy]: the opposite edges stay, the frame stays inside the canvas, at
    /// least `minFrame` across, and the dragged edges snap like a move's.
    public func resized(_ start: Rect2D, handle: CollageHandle, dx: Double, dy: Double, excluding id: String)
        -> Rect2D
    {
        let others = items.filter { $0.id != id }.map(\.frame)
        let w = canvas.size.width
        let h = canvas.size.height
        var left = start.x
        var right = start.maxX
        var top = start.y
        var bottom = start.maxY
        if handle.movesLeft {
            let targets: [Double] = [0] + others.flatMap { [$0.x, $0.maxX] as [Double] }
            left += dx
            left += Self.snapOffset(of: [left], to: targets)
            left = min(max(0, left), right - Self.minFrame)
        }
        if handle.movesRight {
            let targets: [Double] = [w] + others.flatMap { [$0.x, $0.maxX] as [Double] }
            right += dx
            right += Self.snapOffset(of: [right], to: targets)
            right = max(min(w, right), left + Self.minFrame)
        }
        if handle.movesTop {
            let targets: [Double] = [0] + others.flatMap { [$0.y, $0.maxY] as [Double] }
            top += dy
            top += Self.snapOffset(of: [top], to: targets)
            top = min(max(0, top), bottom - Self.minFrame)
        }
        if handle.movesBottom {
            let targets: [Double] = [h] + others.flatMap { [$0.y, $0.maxY] as [Double] }
            bottom += dy
            bottom += Self.snapOffset(of: [bottom], to: targets)
            bottom = max(min(h, bottom), top + Self.minFrame)
        }
        return Rect2D(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// How far to shift so the nearest of [values] lands on one of [targets], within `snapDistance`; 0 when none is
    /// close enough.
    static func snapOffset(of values: [Double], to targets: [Double]) -> Double {
        var best: Double?
        for v in values {
            for t in targets {
                let d = t - v
                if abs(d) <= snapDistance, best == nil || abs(d) < abs(best!) { best = d }
            }
        }
        return best ?? 0
    }

    // MARK: Drawing

    /// [focus] after the photo [image] inside [frame] is dragged by [dx], [dy] canvas pixels (the picture follows the
    /// pointer; an axis with no overflow stays put).
    public static func panned(_ focus: Point2D, image: Size2D, in frame: Rect2D, dx: Double, dy: Double) -> Point2D {
        let cover = coverRect(image: image, in: frame)
        let overflowX = cover.width - frame.width
        let overflowY = cover.height - frame.height
        let x = overflowX > 1e-9 ? focus.x - dx / overflowX : focus.x
        let y = overflowY > 1e-9 ? focus.y - dy / overflowY : focus.y
        return Point2D(x: min(1, max(0, x)), y: min(1, max(0, y)))
    }

    /// Where a photo of [image] size is drawn so it fills [frame] (the overflow cropped; [focus] picks which part
    /// shows, centred by default).
    public static func coverRect(image: Size2D, in frame: Rect2D, focus: Point2D = CollageItem.centred) -> Rect2D {
        guard image.width > 0, image.height > 0 else { return frame }
        let scale = max(frame.width / image.width, frame.height / image.height)
        let w = image.width * scale
        let h = image.height * scale
        return Rect2D(
            x: frame.x + (frame.width - w) * focus.x, y: frame.y + (frame.height - h) * focus.y, width: w, height: h)
    }
}
