/// RawBoy's design tokens ("The Darkroom Bench", RawBoy's DESIGN.md), as plain values so every platform can use them.
/// Keep them identical to RawBoy's: `tools/check-design-tokens.sh` compares them with a RawBoy checkout.
public enum DesignTokens {
    /// Colours as 0xRRGGBB.
    public enum Colour {
        /// Window and photo background. The photo area stays neutral: nothing tinted touches it.
        public static let inkBlack: UInt32 = 0x121212
        /// Edge panels, sidebar.
        public static let graphiteSurface: UInt32 = 0x1C1C1E
        /// Buttons, hovered rows, thumbnail cells.
        public static let graphiteRaised: UInt32 = 0x26262A
        /// Borders and row dividers.
        public static let hairline: UInt32 = 0x333338
        /// Text.
        public static let paperWhite: UInt32 = 0xECECEC
        /// Labels and hints.
        public static let ashMuted: UInt32 = 0x9A9AA2
        /// The one accent: the current choice, the primary action, focus, the pick flag.
        public static let safelightAmber: UInt32 = 0xE8A33D
        /// Text on amber.
        public static let amberInk: UInt32 = 0x1A1206
        /// Errors, the reject flag.
        public static let warningRed: UInt32 = 0xFF6B6B
    }

    /// Corner radii in points.
    public enum Radius {
        public static let chip: Double = 6
        public static let segment: Double = 7
        public static let control: Double = 8
        public static let card: Double = 12
    }

    /// Spacing in points.
    public enum Spacing {
        public static let xs: Double = 4
        public static let sm: Double = 8
        public static let md: Double = 16
        public static let lg: Double = 20
        public static let xl: Double = 24
    }

    /// Font sizes in points (the system font).
    public enum FontSize {
        public static let display: Double = 26
        public static let title: Double = 18
        public static let body: Double = 14
        public static let label: Double = 12
    }

    /// The smallest touch target, in points, when the last input was touch.
    public static let minTouchTarget: Double = 44
}
