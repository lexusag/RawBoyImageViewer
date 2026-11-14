import RawBoyBrowseKit
import Testing

/// Pins the tokens to RawBoy's DESIGN.md values, so a change here has to be a deliberate one in both repos.
struct DesignTokensTests {
    @Test func coloursMatchRawBoy() {
        #expect(DesignTokens.Colour.inkBlack == 0x121212)
        #expect(DesignTokens.Colour.graphiteSurface == 0x1C1C1E)
        #expect(DesignTokens.Colour.graphiteRaised == 0x26262A)
        #expect(DesignTokens.Colour.hairline == 0x333338)
        #expect(DesignTokens.Colour.paperWhite == 0xECECEC)
        #expect(DesignTokens.Colour.ashMuted == 0x9A9AA2)
        #expect(DesignTokens.Colour.safelightAmber == 0xE8A33D)
        #expect(DesignTokens.Colour.amberInk == 0x1A1206)
        #expect(DesignTokens.Colour.warningRed == 0xFF6B6B)
    }
}
