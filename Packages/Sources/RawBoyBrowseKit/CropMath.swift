/// A crop as RawBoy keeps it: edges as fractions (0...1) of the rotated (and, in RawBoy, straightened) frame.
/// A port of RawBoy's `CropMath.ts` (the parts a viewer needs): keep the two in step.
public struct CropRect: Equatable, Hashable, Sendable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double

    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    public static let full = CropRect(left: 0, top: 0, right: 1, bottom: 1)

    public var isFull: Bool { left <= 0 && top <= 0 && right >= 1 && bottom >= 1 }
    public var width: Double { right - left }
    public var height: Double { bottom - top }
}

public enum CropHandle: String, Sendable {
    case move, left, top, right, bottom, topLeft, topRight, bottomLeft, bottomRight
}

/// The crop tool's aspect ratios (RawBoy's list), long side : short side; the orientation is chosen separately.
public enum CropAspect: String, CaseIterable, Sendable {
    case free, original
    case square = "1:1"
    case fiveFour = "5:4"
    case fourThree = "4:3"
    case threeTwo = "3:2"
    case sixteenNine = "16:9"
    case twoOne = "2:1"
    case scope = "2.39:1"

    public func label(portrait: Bool) -> String {
        switch self {
        case .free: return "Free"
        case .original: return "Original"
        case .square: return rawValue
        default:
            let parts = rawValue.split(separator: ":")
            return portrait ? "\(parts[1]):\(parts[0])" : rawValue
        }
    }

    /// Width / height in pixels, or nil for free.
    public func ratio(frameWidth: Double, frameHeight: Double, portrait: Bool) -> Double? {
        switch self {
        case .free: return nil
        case .original:
            let r = frameWidth / frameHeight
            return portrait ? min(r, 1 / r) : max(r, 1 / r)
        default:
            let parts = rawValue.split(separator: ":").compactMap { Double($0) }
            return portrait ? parts[1] / parts[0] : parts[0] / parts[1]
        }
    }
}

public enum CropMath {
    /// Smallest crop side in frame pixels.
    public static let minPixels = 64.0

    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

    static func fromPixels(_ l: Double, _ t: Double, _ r: Double, _ b: Double, _ fw: Double, _ fh: Double) -> CropRect {
        CropRect(
            left: clamp(l / fw, 0, 1), top: clamp(t / fh, 0, 1), right: clamp(r / fw, 0, 1), bottom: clamp(b / fh, 0, 1)
        )
    }

    /// The crop after turning the picture by [quarterTurns] clockwise quarter turns.
    public static func rotate(_ r: CropRect, quarterTurns: Int) -> CropRect {
        var c = r
        for _ in 0..<(((quarterTurns % 4) + 4) % 4) {
            // Clockwise: frame point (x, y) moves to (1 - y, x).
            c = CropRect(left: 1 - c.bottom, top: c.left, right: 1 - c.top, bottom: c.right)
        }
        return c
    }

    /// The crop after mirroring the picture left-right.
    public static func mirror(_ r: CropRect) -> CropRect {
        CropRect(left: 1 - r.right, top: r.top, right: 1 - r.left, bottom: r.bottom)
    }

    /// [r] reshaped to [ratio] (width / height in pixels) with about the same area, around the same centre, inside the
    /// frame. Nil ratio = free: [r] unchanged.
    public static func withAspect(_ r: CropRect, ratio: Double?, frameWidth fw: Double, frameHeight fh: Double)
        -> CropRect
    {
        guard let ratio else { return r }
        let area = r.width * fw * r.height * fh
        var w = (area * ratio).squareRoot()
        var h = w / ratio
        let fit = min(1, fw / w, fh / h)
        w *= fit
        h *= fit
        let cx = clamp((r.left + r.right) / 2 * fw, w / 2, fw - w / 2)
        let cy = clamp((r.top + r.bottom) / 2 * fh, h / 2, fh - h / 2)
        return fromPixels(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2, fw, fh)
    }

    /// [start] after dragging [handle] by ([dx], [dy]) in frame fractions, kept inside the frame, at least [minPixels]
    /// wide and high, and at [ratio] (width / height in pixels) when not nil.
    public static func drag(
        _ start: CropRect, _ handle: CropHandle, dx: Double, dy: Double, ratio: Double?, frameWidth fw: Double,
        frameHeight fh: Double
    ) -> CropRect {
        let minW = min(minPixels, fw)
        let minH = min(minPixels, fh)
        let l = start.left * fw
        let t = start.top * fh
        let r = start.right * fw
        let b = start.bottom * fh
        let mx = dx * fw
        let my = dy * fh

        if handle == .move {
            let ox = clamp(mx, -l, fw - r)
            let oy = clamp(my, -t, fh - b)
            return fromPixels(l + ox, t + oy, r + ox, b + oy, fw, fh)
        }
        let movesLeft = [.left, .topLeft, .bottomLeft].contains(handle)
        let movesRight = [.right, .topRight, .bottomRight].contains(handle)
        let movesTop = [.top, .topLeft, .topRight].contains(handle)
        let movesBottom = [.bottom, .bottomLeft, .bottomRight].contains(handle)

        guard let ratio else {
            let nl = movesLeft ? clamp(l + mx, 0, r - minW) : l
            let nr = movesRight ? clamp(r + mx, l + minW, fw) : r
            let nt = movesTop ? clamp(t + my, 0, b - minH) : t
            let nb = movesBottom ? clamp(b + my, t + minH, fh) : b
            return fromPixels(nl, nt, nr, nb, fw, fh)
        }
        let horizontal = movesLeft || movesRight
        let vertical = movesTop || movesBottom
        // Anchor: the opposite edge (or corner); a single edge keeps the other axis centred.
        let ax = movesLeft ? r : movesRight ? l : (l + r) / 2
        let ay = movesTop ? b : movesBottom ? t : (t + b) / 2
        let wantW = horizontal ? abs((movesLeft ? l + mx : r + mx) - ax) : 0
        let wantH = vertical ? abs((movesTop ? t + my : b + my) - ay) : 0
        var w = max(wantW, wantH * ratio)
        // Room around the anchor, per axis (both halves when that axis stays centred).
        let roomW = movesLeft ? ax : movesRight ? fw - ax : 2 * min(ax, fw - ax)
        let roomH = movesTop ? ay : movesBottom ? fh - ay : 2 * min(ay, fh - ay)
        let room = min(roomW, roomH * ratio)
        w = min(max(min(w, room), minW, minH * ratio), room)
        let h = w / ratio
        let nl = movesLeft ? ax - w : movesRight ? ax : ax - w / 2
        let nt = movesTop ? ay - h : movesBottom ? ay : ay - h / 2
        return fromPixels(nl, nt, nl + w, nt + h, fw, fh)
    }

    /// The handle under frame point ([x], [y]) (fractions), with grab distances [tolX], [tolY] in fractions: corners
    /// first, then edges, then inside = move. Nil outside the crop.
    public static func handle(at r: CropRect, x: Double, y: Double, tolX: Double, tolY: Double) -> CropHandle? {
        let nearL = abs(x - r.left) <= tolX
        let nearR = abs(x - r.right) <= tolX
        let nearT = abs(y - r.top) <= tolY
        let nearB = abs(y - r.bottom) <= tolY
        let inX = x >= r.left - tolX && x <= r.right + tolX
        let inY = y >= r.top - tolY && y <= r.bottom + tolY
        guard inX, inY else { return nil }
        if nearT && nearL { return .topLeft }
        if nearT && nearR { return .topRight }
        if nearB && nearL { return .bottomLeft }
        if nearB && nearR { return .bottomRight }
        if nearL { return .left }
        if nearR { return .right }
        if nearT { return .top }
        if nearB { return .bottom }
        return .move
    }
}
