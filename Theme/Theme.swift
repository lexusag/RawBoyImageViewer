import AppKit
import RawBoyBrowseKit
import SwiftUI

/// RawBoy's design tokens as SwiftUI values. The values themselves live in `DesignTokens` (RawBoyBrowseKit).
enum Theme {
    static let inkBlack = Color(hex: DesignTokens.Colour.inkBlack)
    static let graphiteSurface = Color(hex: DesignTokens.Colour.graphiteSurface)
    static let graphiteRaised = Color(hex: DesignTokens.Colour.graphiteRaised)
    static let hairline = Color(hex: DesignTokens.Colour.hairline)
    static let paperWhite = Color(hex: DesignTokens.Colour.paperWhite)
    static let ashMuted = Color(hex: DesignTokens.Colour.ashMuted)
    static let amber = Color(hex: DesignTokens.Colour.safelightAmber)
    static let amberInk = Color(hex: DesignTokens.Colour.amberInk)
    static let warningRed = Color(hex: DesignTokens.Colour.warningRed)

    static let display = Font.system(size: DesignTokens.FontSize.display, weight: .bold)
    static let title = Font.system(size: DesignTokens.FontSize.title, weight: .semibold)
    static let body = Font.system(size: DesignTokens.FontSize.body)
    static let label = Font.system(size: DesignTokens.FontSize.label)
}

extension Color {
    /// A colour from 0xRRGGBB, in sRGB.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// RawBoy's buttons: graphite with a hairline, or amber for the one primary action in an area.
struct RawBoyButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .foregroundStyle(primary ? Theme.amberInk : Theme.paperWhite)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .fill(primary ? Theme.amber : Theme.graphiteRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                    .strokeBorder(primary ? Color.clear : Theme.hairline)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == RawBoyButtonStyle {
    static var rawBoy: RawBoyButtonStyle { RawBoyButtonStyle() }
    static var rawBoyPrimary: RawBoyButtonStyle { RawBoyButtonStyle(primary: true) }
}

extension NSColor {
    /// A colour from 0xRRGGBB, in sRGB.
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }
}
