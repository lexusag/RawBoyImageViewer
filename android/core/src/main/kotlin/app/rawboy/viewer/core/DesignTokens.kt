package app.rawboy.viewer.core

/**
 * RawBoy's "Darkroom Bench" design tokens.
 * A port of RawBoyBrowseKit's `DesignTokens.swift`: keep the two in step.
 */
object DesignTokens {
    object Colour {
        const val inkBlack: Long = 0xFF121212
        const val graphiteSurface: Long = 0xFF1C1C1E
        const val graphiteRaised: Long = 0xFF26262A
        const val hairline: Long = 0xFF333338
        const val paperWhite: Long = 0xFFECECEC
        const val ashMuted: Long = 0xFF9A9AA2
        const val safelightAmber: Long = 0xFFE8A33D
        const val amberInk: Long = 0xFF1A1206
        const val warningRed: Long = 0xFFFF6B6B
    }

    object Radius {
        const val chip: Int = 6
        const val segment: Int = 7
        const val control: Int = 8
        const val card: Int = 12
    }

    object Spacing {
        const val xs: Int = 4
        const val sm: Int = 8
        const val md: Int = 16
        const val lg: Int = 20
        const val xl: Int = 24
    }

    object FontSize {
        const val display: Int = 26
        const val title: Int = 18
        const val body: Int = 14
        const val label: Int = 12
    }

    const val minTouchTarget: Int = 48
}
