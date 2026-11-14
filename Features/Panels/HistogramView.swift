import RawBoyBrowseKit
import SwiftUI

/// The photo's red, green and blue levels, with the share of crushed shadows (left) and clipped highlights (right).
/// Clicking it shows those pixels on the photo. A port of RawBoy's HistogramView (same channel colours, additive, the
/// same indicators), in this app's card style.
struct HistogramView: View {
    let histogram: Histogram?
    /// The clipping warning is on: marked by the amber border.
    let active: Bool
    let onTap: () -> Void

    static let red = Color(red: 0.90, green: 0.27, blue: 0.24)
    static let green = Color(red: 0.27, green: 0.78, blue: 0.35)
    static let blue = Color(red: 0.27, green: 0.47, blue: 0.94)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.chip)
        ZStack {
            Canvas { ctx, size in
                guard let h = histogram else { return }
                ctx.clip(to: Path(CGRect(origin: .zero, size: size)))
                // Overlaps add up: red + green reads yellow, all three white.
                ctx.blendMode = .plusLighter
                for (bins, color) in [(h.red, Self.red), (h.green, Self.green), (h.blue, Self.blue)] {
                    ctx.fill(Self.area(bins, peak: h.peak, size: size), with: .color(color.opacity(0.75)))
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 3)
            HStack(alignment: .bottom) {
                indicator(histogram?.shadows ?? 0, Color(red: 0.35, green: 0.55, blue: 1), leading: true)
                Spacer(minLength: 0)
                indicator(histogram?.highlights ?? 0, Color(red: 1, green: 0.3, blue: 0.25), leading: false)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(5)
        }
        .background(Theme.inkBlack, in: shape)
        .overlay(shape.strokeBorder(active ? Theme.amber : Theme.hairline, lineWidth: active ? 1.5 : 1))
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture(perform: onTap)
        .help(active ? "Hide clipping (J)" : "Show clipped highlights red and crushed shadows blue (J)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Histogram")
        .accessibilityValue(
            histogram.map {
                "Shadows clipped \(Histogram.percent($0.shadows)), highlights clipped \(Histogram.percent($0.highlights))"
            } ?? ""
        )
        .accessibilityAddTraits(.isButton)
    }

    /// A dot (grey, or [color] once clipped) with the clipped share next to it.
    private func indicator(_ fraction: Double, _ color: Color, leading: Bool) -> some View {
        let on = fraction > Histogram.clipShown
        let dot = Circle().fill(on ? color : Theme.ashMuted.opacity(0.6)).frame(width: 6, height: 6)
        return HStack(spacing: 3) {
            if leading { dot }
            if on {
                Text(Histogram.percent(fraction))
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.paperWhite)
            }
            if !leading { dot }
        }
    }

    /// One channel as a filled area; bins above [peak] (the clipped end bins) run off the top.
    static func area(_ bins: [Int], peak: Int, size: CGSize) -> Path {
        var path = Path()
        guard bins.count > 1 else { return path }
        let step = size.width / CGFloat(bins.count - 1)
        let p = CGFloat(max(1, peak))
        path.move(to: CGPoint(x: 0, y: size.height))
        for (i, n) in bins.enumerated() {
            path.addLine(to: CGPoint(x: CGFloat(i) * step, y: size.height - min(1, CGFloat(n) / p) * size.height))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }
}
