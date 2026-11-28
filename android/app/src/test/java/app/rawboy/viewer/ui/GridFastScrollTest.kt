package app.rawboy.viewer.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GridFastScrollTest {
    @Test
    fun fractionIsZeroAtTopAndOneAtEnd() {
        assertEquals(0f, fastScrollFraction(0, 1000, 20), 0f)
        assertEquals(1f, fastScrollFraction(980, 1000, 20), 0f)
        assertEquals(1f, fastScrollFraction(999, 1000, 20), 0f)
    }

    @Test
    fun targetIndexMapsProportionally() {
        assertEquals(0, fastScrollTargetIndex(0f, 1000, 20))
        assertEquals(490, fastScrollTargetIndex(0.5f, 1000, 20))
        assertEquals(980, fastScrollTargetIndex(1f, 1000, 20))
        assertEquals(980, fastScrollTargetIndex(2f, 1000, 20))
    }

    @Test
    fun shortListsNeedNoThumb() {
        assertFalse(fastScrollNeeded(30, 20))
        assertFalse(fastScrollNeeded(60, 20))
        assertTrue(fastScrollNeeded(61, 20))
        assertFalse(fastScrollNeeded(100, 0))
        assertEquals(0, fastScrollTargetIndex(0.7f, 10, 20))
    }
}
