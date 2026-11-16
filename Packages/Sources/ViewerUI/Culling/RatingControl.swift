import RawBoyBrowseKit
import SwiftUI

/// Stars 1–5, Pick and Reject as buttons: the current rating filled in amber (pick) or red (reject). Clicking the
/// stars a photo has clears them, as the same key does.
struct RatingControl: View {
    let rating: Rating
    var compact = false
    let onStars: (Int) -> Void
    let onFlag: (Flag) -> Void

    var body: some View {
        HStack(spacing: compact ? 2 : 4) {
            ForEach(1...5, id: \.self) { n in
                Button {
                    onStars(n)
                } label: {
                    Image(systemName: n <= rating.stars ? "star.fill" : "star")
                        .font(.system(size: compact ? 13 : 15))
                        .foregroundStyle(n <= rating.stars ? Theme.amber : Theme.ashMuted)
                        .frame(width: compact ? 22 : 26, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(n) star\(n == 1 ? "" : "s") (\(n))")
                .accessibilityLabel("\(n) star\(n == 1 ? "" : "s")")
            }
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 18).padding(.horizontal, 4)
            FlagButton(
                icon: "flag.fill", title: "Pick", key: "P", isOn: rating.flag == .pick, onColour: Theme.amber,
                compact: compact
            ) { onFlag(.pick) }
            FlagButton(
                icon: "xmark", title: "Reject", key: "X", isOn: rating.flag == .reject, onColour: Theme.warningRed,
                compact: compact
            ) { onFlag(.reject) }
        }
    }
}

private struct FlagButton: View {
    let icon: String
    let title: String
    let key: String
    let isOn: Bool
    let onColour: Color
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                if !compact { Text(title).font(Theme.label) }
            }
            .foregroundStyle(isOn ? Theme.amberInk : Theme.paperWhite)
            .padding(.horizontal, compact ? 7 : 9)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.chip).fill(isOn ? onColour : Theme.graphiteRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.chip).strokeBorder(isOn ? .clear : Theme.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(title) (\(key)); again to unflag")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A photo's rating as a small badge on its thumbnail: "★★★", a pick flag, or a reject cross.
struct RatingBadge: View {
    let rating: Rating

    var body: some View {
        if rating.isRated {
            HStack(spacing: 3) {
                if rating.flag == .reject {
                    Image(systemName: "xmark").foregroundStyle(Theme.warningRed)
                } else {
                    if rating.stars > 0 {
                        Text(String(repeating: "★", count: rating.stars)).foregroundStyle(Theme.amber)
                    }
                    if rating.flag == .pick { Image(systemName: "flag.fill").foregroundStyle(Theme.amber) }
                }
            }
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(Theme.graphiteSurface.opacity(0.92)))
        }
    }
}
