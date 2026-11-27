package app.rawboy.viewer.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FullScreenViewerLogicTest {
    @Test
    fun filmstripCentresMiddleItemExactly() {
        val itemWidth = 112
        val spacing = 12
        val pitch = itemWidth + spacing
        val viewport = 800

        val target = filmstripCenterPosition(
            index = 50,
            count = 100,
            viewportWidthPx = viewport,
            itemWidthPx = itemWidth,
            spacingPx = spacing,
        )

        assertTrue(target.offsetPx in 0 until pitch)
        val renderedLeft = (50 - target.index) * pitch - target.offsetPx
        val renderedCentre = renderedLeft + itemWidth / 2
        assertEquals(viewport / 2, renderedCentre)
    }

    @Test
    fun filmstripClampsAtStartEndAndShortLists() {
        val itemWidth = 112
        val spacing = 12
        val pitch = itemWidth + spacing
        val viewport = 800

        // Start of list
        assertEquals(
            FilmstripScrollTarget(0, 0),
            filmstripCenterPosition(index = 0, count = 100, viewportWidthPx = viewport, itemWidthPx = itemWidth, spacingPx = spacing),
        )

        // End of list aligns right edge with viewport
        val endTarget = filmstripCenterPosition(index = 99, count = 100, viewportWidthPx = viewport, itemWidthPx = itemWidth, spacingPx = spacing)
        assertTrue(endTarget.offsetPx in 0 until pitch)
        val lastRightEdge = (99 - endTarget.index) * pitch - endTarget.offsetPx + itemWidth
        assertEquals(viewport, lastRightEdge)

        // All items fit in viewport -> no scroll
        assertEquals(
            FilmstripScrollTarget(0, 0),
            filmstripCenterPosition(index = 2, count = 4, viewportWidthPx = viewport, itemWidthPx = itemWidth, spacingPx = spacing),
        )

        // Empty list and invalid viewport handled safely
        assertEquals(
            FilmstripScrollTarget(0, 0),
            filmstripCenterPosition(index = 5, count = 0, viewportWidthPx = viewport, itemWidthPx = itemWidth, spacingPx = spacing),
        )
        assertEquals(
            FilmstripScrollTarget(10, 0),
            filmstripCenterPosition(index = 10, count = 20, viewportWidthPx = 0, itemWidthPx = itemWidth, spacingPx = spacing),
        )
    }

    @Test
    fun filmstripClampsOutOfRangeAndLargeCounts() {
        val low = filmstripCenterPosition(index = -5, count = 50, viewportWidthPx = 800, itemWidthPx = 112, spacingPx = 12)
        assertEquals(FilmstripScrollTarget(0, 0), low)

        val high = filmstripCenterPosition(index = 500, count = 50, viewportWidthPx = 800, itemWidthPx = 112, spacingPx = 12)
        val last = filmstripCenterPosition(index = 49, count = 50, viewportWidthPx = 800, itemWidthPx = 112, spacingPx = 12)
        assertEquals(last, high)

        val huge = filmstripCenterPosition(index = 40_000, count = 50_000, viewportWidthPx = 1200, itemWidthPx = 168, spacingPx = 18)
        assertTrue(huge.index in 39_990..40_000)
        assertTrue(huge.offsetPx in 0 until (168 + 18))
    }

    @Test
    fun swipeDismissThresholdClampsToBounds() {
        val density = 2f
        // Compact landscape height: 360dp * 0.18 = 64.8dp -> clamps to 100dp (200px)
        assertEquals(200f, swipeDismissThresholdPx(containerHeightPx = 720, density = density), 0.01f)
        // Portrait phone height: 750dp * 0.18 = 135dp (270px)
        assertEquals(270f, swipeDismissThresholdPx(containerHeightPx = 1500, density = density), 0.01f)
        // Tall tablet height: 1200dp * 0.18 = 216dp -> clamps to 180dp (360px)
        assertEquals(360f, swipeDismissThresholdPx(containerHeightPx = 2400, density = density), 0.01f)
    }

    @Test
    fun shouldDismissOnSwipeDownHandlesDistanceFlingAndCancel() {
        val density = 2f
        val heightPx = 1500 // threshold = 270px (135dp)

        // Zero or negative drag never dismisses
        assertFalse(shouldDismissOnSwipeDown(dragDistancePx = 0f, velocityYPxPerSec = 2000f, containerHeightPx = heightPx, density = density))
        assertFalse(shouldDismissOnSwipeDown(dragDistancePx = -50f, velocityYPxPerSec = 2000f, containerHeightPx = heightPx, density = density))

        // Short slow drag stays open
        assertFalse(shouldDismissOnSwipeDown(dragDistancePx = 150f, velocityYPxPerSec = 200f, containerHeightPx = heightPx, density = density))

        // Drag past threshold with calm release closes
        assertTrue(shouldDismissOnSwipeDown(dragDistancePx = 280f, velocityYPxPerSec = 0f, containerHeightPx = heightPx, density = density))

        // Drag past threshold then flicking sharply back up cancels dismiss
        assertFalse(shouldDismissOnSwipeDown(dragDistancePx = 300f, velocityYPxPerSec = -600f, containerHeightPx = heightPx, density = density))

        // Quick downward flick above minimum drag closes even below distance threshold
        assertTrue(shouldDismissOnSwipeDown(dragDistancePx = 80f, velocityYPxPerSec = 1600f, containerHeightPx = heightPx, density = density))

        // Tiny downward flick below minimum drag does not close
        assertFalse(shouldDismissOnSwipeDown(dragDistancePx = 40f, velocityYPxPerSec = 2500f, containerHeightPx = heightPx, density = density))
    }
}
