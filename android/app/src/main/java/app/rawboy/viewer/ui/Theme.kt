package app.rawboy.viewer.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import app.rawboy.viewer.core.DesignTokens

object DarkroomColours {
    val InkBlack = Color(DesignTokens.Colour.inkBlack)
    val GraphiteSurface = Color(DesignTokens.Colour.graphiteSurface)
    val GraphiteRaised = Color(DesignTokens.Colour.graphiteRaised)
    val Hairline = Color(DesignTokens.Colour.hairline)
    val PaperWhite = Color(DesignTokens.Colour.paperWhite)
    val AshMuted = Color(DesignTokens.Colour.ashMuted)
    val SafelightAmber = Color(DesignTokens.Colour.safelightAmber)
    val AmberInk = Color(DesignTokens.Colour.amberInk)
    val WarningRed = Color(DesignTokens.Colour.warningRed)
}

private val DarkroomScheme = darkColorScheme(
    primary = DarkroomColours.SafelightAmber,
    onPrimary = DarkroomColours.AmberInk,
    secondary = DarkroomColours.SafelightAmber,
    onSecondary = DarkroomColours.AmberInk,
    background = DarkroomColours.InkBlack,
    onBackground = DarkroomColours.PaperWhite,
    surface = DarkroomColours.GraphiteSurface,
    onSurface = DarkroomColours.PaperWhite,
    surfaceVariant = DarkroomColours.GraphiteRaised,
    onSurfaceVariant = DarkroomColours.AshMuted,
    outline = DarkroomColours.Hairline,
    error = DarkroomColours.WarningRed,
    onError = DarkroomColours.InkBlack,
)

@Composable
fun RawBoyViewerTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkroomScheme,
        content = content,
    )
}
