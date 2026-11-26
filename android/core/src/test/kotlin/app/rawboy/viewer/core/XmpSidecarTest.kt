package app.rawboy.viewer.core

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class XmpSidecarTest {
    private val xmpDir: File
        get() = File(System.getProperty("fixtures.dir") ?: "../Packages/Tests/RawBoyBrowseKitTests/Fixtures", "Xmp")

    @Test
    fun readsAllSharedFixturesMatchingExpectedJson() {
        val expected = JSONObject(File(xmpDir, "expected.json").readText(Charsets.UTF_8))
        val keys = expected.keys()
        var checked = 0
        while (keys.hasNext()) {
            val fileName = keys.next()
            val exp = expected.getJSONObject(fileName)
            val text = File(xmpDir, fileName).readText(Charsets.UTF_8)

            val rating = XmpSidecar.readRating(text)
            assertEquals("$fileName stars", exp.getInt("stars"), rating.stars)
            val expFlag = if (exp.isNull("flag")) null else Flag.fromRaw(exp.getString("flag"))
            assertEquals("$fileName flag", expFlag, rating.flag)

            val expOri = if (exp.isNull("orientation")) null else exp.getInt("orientation")
            assertEquals("$fileName orientation", expOri, XmpSidecar.readOrientation(text))

            val expDev = if (exp.isNull("develop")) null else exp.getString("develop")
            assertEquals("$fileName develop", expDev, XmpSidecar.readDevelop(text))

            val expAuto = if (exp.isNull("auto")) null else exp.getString("auto")
            assertEquals("$fileName auto", expAuto, XmpSidecar.readAuto(text))
            checked++
        }
        assertTrue("Expected at least 5 shared XMP fixtures", checked >= 5)
    }

    @Test
    fun writePreservesCrlfAndUnrelatedFieldsByteForByte() {
        val crlf = File(xmpDir, "crlf.xmp").readText(Charsets.UTF_8)
        assertTrue(crlf.contains("\r\n"))

        val updated = XmpSidecar.writeRating(crlf, Rating(stars = 5, flag = null))
        assertEquals(Rating(stars = 5, flag = null), XmpSidecar.readRating(updated))
        assertEquals(crlf.replace("xmp:Rating=\"2\"", "xmp:Rating=\"5\""), updated)
    }

    @Test
    fun writeToNewAndExistingSidecarsRoundTrips() {
        val fresh = XmpSidecar.writeRating(null, Rating(stars = 4, flag = Flag.PICK))
        assertEquals(Rating(stars = 4, flag = Flag.PICK), XmpSidecar.readRating(fresh))
        assertTrue(XmpSidecar.hasRating(fresh))

        val rejected = XmpSidecar.writeRating(fresh, Rating(stars = 0, flag = Flag.REJECT))
        assertEquals(Rating(stars = 0, flag = Flag.REJECT), XmpSidecar.readRating(rejected))
        assertFalse(rejected.contains("rawboy:Pick"))

        val cleared = XmpSidecar.writeRating(rejected, Rating.NONE)
        assertEquals(Rating.NONE, XmpSidecar.readRating(cleared))
    }

    @Test
    fun elementFormPreservedWhenEdited() {
        val text = File(xmpDir, "element-form.xmp").readText(Charsets.UTF_8)
        val out = XmpSidecar.writeRating(text, Rating(stars = 3, flag = null))
        assertEquals(Rating(stars = 3, flag = null), XmpSidecar.readRating(out))
        assertTrue(out.contains("<xmp:Rating>3</xmp:Rating>"))
        assertFalse(out.contains("rawboy:Pick"))
        assertEquals(XmpSidecar.readDevelop(text), XmpSidecar.readDevelop(out))
    }

    @Test(expected = XmpWriteException::class)
    fun nonSidecarThrowsOnWrite() {
        XmpSidecar.writeRating("<not-xmp/>", Rating(stars = 3))
    }
}
