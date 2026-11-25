package app.rawboy.viewer.core

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.time.ZoneOffset

class CoreTests {
    @Test
    fun photoFileTypeAndGroups() {
        assertEquals(PhotoFileType.RAW, PhotoFileType.of("IMG_0001.CR3"))
        assertEquals(PhotoFileType.DISPLAY, PhotoFileType.of("IMG_0001.JPG"))
        assertEquals(PhotoFileType.VIDEO, PhotoFileType.of("CLIP.MOV"))
        assertNull(PhotoFileType.of(".hidden"))
        assertNull(PhotoFileType.of("notes.txt"))

        val groups = PhotoGroups.group(
            listOf(
                "IMG_10.JPG",
                "IMG_2.CR3",
                "IMG_2.JPG",
                "IMG_2.CR3.xmp",
                "IMG_2_01.CR3.xmp",
                "IMG_10.xmp",
                "README.txt",
            )
        )
        assertEquals(2, groups.size)
        assertEquals("IMG_2.CR3", groups[0].main)
        assertEquals(listOf("IMG_2.JPG"), groups[0].companions)
        assertEquals(listOf("IMG_2.CR3.xmp", "IMG_2_01.CR3.xmp"), groups[0].sidecars)
        assertEquals(listOf("IMG_2.CR3.xmp", "IMG_2_01.CR3.xmp"), PhotoGroups.sidecarNamesToWrite(groups[0]))
        assertEquals("IMG_10.JPG", groups[1].main)
        assertEquals(listOf("IMG_10.xmp"), groups[1].sidecars)

        val noSidecar = PhotoGroup("DSC0001", "DSC0001.ARW", emptyList(), emptyList())
        assertEquals(listOf("DSC0001.xmp"), PhotoGroups.sidecarNamesToWrite(noSidecar))
    }

    @Test
    fun photoOrderAndRating() {
        assertEquals("2026:03:01 12:23:15", PhotoOrder.validDate("2026:03:01 12:23:15\u0000"))
        assertNull(PhotoOrder.validDate("0000:00:00 00:00:00"))
        assertEquals("1970:01:01 00:00:01", PhotoOrder.fileDate(1000L, ZoneOffset.UTC))
        assertTrue(PhotoOrder.compareNames("IMG_9.CR3", "IMG_10.CR3") < 0)
        assertTrue(PhotoOrder.inOrder(PhotoSort.DATE, "2026:01:01 10:00:00" to "B.ARW", "2026:01:02 10:00:00" to "A.ARW"))
        assertTrue(PhotoOrder.inOrder(PhotoSort.DATE, "2026:01:01 10:00:00" to "B.ARW", null to "A.ARW"))

        val rated = Rating.withStars(listOf(Rating(stars = 0, flag = Flag.REJECT)), 3)
        assertEquals(listOf(Rating(stars = 3, flag = null)), rated)
        assertEquals(listOf(Rating(stars = 0, flag = null)), Rating.withStars(rated, 3))

        val counts = FlagFilter.counts(listOf(Rating(flag = Flag.PICK), Rating(flag = Flag.REJECT), Rating.NONE))
        assertEquals(3, counts[FlagFilter.ALL])
        assertEquals(1, counts[FlagFilter.PICKS])
        assertEquals(1, counts[FlagFilter.UNFLAGGED])
        assertEquals(1, counts[FlagFilter.REJECTS])
    }

    @Test
    fun embeddedPreviewFindsLargestAndAppliesRawOrientation() {
        fun syntheticJpeg(w: Int, h: Int, sof: Int = 0xc0): ByteArray = byteArrayOf(
            0xff.toByte(), 0xd8.toByte(),
            0xff.toByte(), sof.toByte(), 0x00, 0x0b, 0x08,
            (h ushr 8).toByte(), (h and 0xff).toByte(),
            (w ushr 8).toByte(), (w and 0xff).toByte(),
            0x01, 0x01, 0x11, 0x00,
            0xff.toByte(), 0xda.toByte(), 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3f, 0x00,
            0x12, 0x34, 0xff.toByte(), 0x00, 0x56,
            0xff.toByte(), 0xd9.toByte(),
        )
        // Build a minimal RAF header pointing to a 3200x2400 JPEG at offset 128
        val jpeg = syntheticJpeg(3200, 2400)
        val buf = ByteArray(128 + jpeg.size)
        "FUJIFILMCCD-RAW".toByteArray().copyInto(buf, 0)
        fun putBe32(at: Int, v: Int) {
            buf[at] = (v ushr 24).toByte()
            buf[at + 1] = (v ushr 16).toByte()
            buf[at + 2] = (v ushr 8).toByte()
            buf[at + 3] = (v and 0xff).toByte()
        }
        putBe32(84, 128)
        putBe32(88, jpeg.size)
        jpeg.copyInto(buf, 128)

        val preview = EmbeddedPreviews.find(BytesSource(buf))
        assertNotNull(preview)
        assertEquals(3200, preview!!.width)
        assertEquals(2400, preview.height)
        assertArrayEquals(jpeg, preview.jpeg(BytesSource(buf)))

        val oriented = EmbeddedPreviews.withOrientation(jpeg, 6)
        assertEquals(6, EmbeddedPreviews.jpegInfo(BytesSource(oriented), 0, oriented.size)?.orientation)
    }

    @Test
    fun blockCachedSourceReadsAcrossBlocks() {
        val raw = ByteArray(200_000) { (it and 0xff).toByte() }
        var reads = 0
        val src = BlockCachedSource(raw.size) { offset, len ->
            reads++
            val s = offset.toInt()
            raw.copyOfRange(s, minOf(s + len, raw.size))
        }
        assertArrayEquals(raw.copyOfRange(65530, 65550), src.read(65530, 20))
        assertEquals(2, reads)
        // Cached second read makes no new I/O
        assertArrayEquals(raw.copyOfRange(65532, 65540), src.read(65532, 8))
        assertEquals(2, reads)
    }

    @Test
    fun exifFormatAndZoomAndLruAndPrefetchAndHistogram() {
        assertEquals("1/250 s", ExifFormat.shutter(1.0 / 250.0))
        assertEquals("2 s", ExifFormat.shutter(2.0))
        assertEquals("f/2.8", ExifFormat.aperture(2.8))
        assertEquals("ISO 400", ExifFormat.iso(400))
        assertEquals("−0.7 EV", ExifFormat.bias(-0.7))
        assertEquals("Canon EOS R5", ExifFormat.camera("Canon", "Canon EOS R5"))
        assertEquals("FUJIFILM GFX 50R", ExifFormat.camera("FUJIFILM", "GFX 50R"))

        val zm = ZoomMath(Size2D(6000.0, 4000.0), Size2D(1000.0, 1000.0), backingScale = 2.0)
        assertTrue(zm.isFit(zm.fit))
        val zoomed = zm.toggled(zm.fit, Point2D.ZERO)
        assertEquals(zm.oneToOneScale, zoomed.scale, 1e-6)
        assertTrue(zm.isFit(zm.toggled(zoomed, Point2D.ZERO)))

        val lru = LRUCache<String, Int>(budget = 10)
        lru.insert(1, "a", 6)
        lru.insert(2, "b", 6)
        assertFalse(lru.contains("a"))
        assertTrue(lru.contains("b"))

        assertEquals(listOf(3, 4, 5, 1), PrefetchPlan.order(current = 2, count = 10, forward = true))

        val hist = Histogram.fromArgb(intArrayOf(0xFFFFFFFF.toInt(), 0xFF000000.toInt(), 0xFF808080.toInt()))
        assertTrue(hist.highlights > 0.3)
        assertTrue(hist.shadows > 0.3)
        assertEquals("33%", Histogram.percent(1.0 / 3.0))
    }
}
