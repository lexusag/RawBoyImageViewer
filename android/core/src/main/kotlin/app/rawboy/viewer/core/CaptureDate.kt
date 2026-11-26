package app.rawboy.viewer.core

/**
 * When a photo was shot, for ordering the browser: EXIF's DateTimeOriginal (else when it was digitised or last
 * written), found as `EmbeddedPreviews` finds previews, reading only the bytes needed, never decoding the raw.
 * A port of RawBoyBrowseKit's `CaptureDate.swift`: keep the two in step.
 */
object CaptureDate {
    private const val TAG_DATE_TIME = 0x0132
    private const val TAG_EXIF_IFD = 0x8769
    private const val TAG_DATE_TIME_ORIGINAL = 0x9003
    private const val TAG_DATE_TIME_DIGITIZED = 0x9004

    /** The capture date as an EXIF date ("YYYY:MM:DD HH:MM:SS", sorts as text), or null. */
    fun find(source: ByteSource): String? {
        val head = source.read(0, 16)
        if (head.size < 16) return null
        if (head.ascii(0, 15) == "FUJIFILMCCD-RAW") return jpegDate(source, source.u32(84, false))
        if (head.ascii(4, 8) == "ftyp") return cr3Date(source)
        if (EmbeddedPreviews.isTiff(head)) return tiffDate(source, 0)
        if (head.u8(0) == 0xff && head.u8(1) == 0xd8) return jpegDate(source, 0)
        return null
    }

    private class IFD(val bytes: ByteArray, val tags: Map<Int, Int>)

    private fun readIFD(source: ByteSource, base: Int, at: Int, le: Boolean): IFD? {
        if (at <= 0 || base.toLong() + at.toLong() + 2 > source.size.toLong()) return null
        val n = source.u16(base + at, le)
        if (n <= 0 || n > 1000) return null
        val bytes = source.read(base + at + 2, n * 12)
        val tags = HashMap<Int, Int>(n * 2)
        var i = 0
        while (i < n && i * 12 + 12 <= bytes.size) {
            tags[bytes.u16(i * 12, le)] = i * 12
            i += 1
        }
        return IFD(bytes, tags)
    }

    private fun date(source: ByteSource, base: Int, ifd: IFD, tag: Int, le: Boolean): String? {
        val p = ifd.tags[tag] ?: return null
        if (ifd.bytes.u16(p + 2, le) != 2 || ifd.bytes.u32(p + 4, le) < 19) return null
        val bytes = source.read(base + ifd.bytes.u32(p + 8, le), 19)
        return if (bytes.size == 19) PhotoOrder.validDate(bytes.ascii(0, 19)) else null
    }

    private fun tiffDate(source: ByteSource, base: Int): String? {
        val header = source.read(base, 8)
        val le = header.u8(0) == 0x49
        val ifd0 = readIFD(source, base, header.u32(4, le), le) ?: return null
        val exifAt = ifd0.tags[TAG_EXIF_IFD]
        if (exifAt != null) {
            val exif = readIFD(source, base, ifd0.bytes.u32(exifAt + 8, le), le)
            if (exif != null) {
                val d = date(source, base, exif, TAG_DATE_TIME_ORIGINAL, le)
                    ?: date(source, base, exif, TAG_DATE_TIME_DIGITIZED, le)
                if (d != null) return d
            }
        }
        return date(source, base, ifd0, TAG_DATE_TIME, le)
    }

    private fun jpegDate(source: ByteSource, offset: Int): String? {
        if (source.u16(offset, false) != 0xffd8) return null
        var at = offset + 2
        var i = 0
        while (i < 32 && at + 4 <= source.size) {
            i += 1
            val m = source.read(at, 4)
            if (m.u8(0) != 0xff) return null
            val marker = m.u8(1)
            if (marker == 0xda || marker == 0xd9) return null
            val size = m.u16(2, false)
            if (marker == 0xe1 && size > 16 && source.read(at + 4, 4).ascii(0, 4) == "Exif") {
                return tiffDate(source, at + 10)
            }
            at += 2 + size
        }
        return null
    }

    private fun cr3Date(source: ByteSource): String? {
        val moov = EmbeddedPreviews.boxes(source, 0, source.size).firstOrNull { it.type == "moov" } ?: return null
        val canon = EmbeddedPreviews.boxes(source, moov.start, moov.end)
            .firstOrNull { it.type == "uuid" && it.uuid == EmbeddedPreviews.CANON_UUID }
            ?: return null
        val inner = EmbeddedPreviews.boxes(source, canon.start, canon.end)
        fun first(start: Int, tags: List<Int>): String? {
            val header = source.read(start, 8)
            val le = header.u8(0) == 0x49
            val ifd = readIFD(source, start, header.u32(4, le), le) ?: return null
            return tags.firstNotNullOfOrNull { date(source, start, ifd, it, le) }
        }
        val cmt2 = inner.firstOrNull { it.type == "CMT2" }
        if (cmt2 != null) {
            first(cmt2.start, listOf(TAG_DATE_TIME_ORIGINAL, TAG_DATE_TIME_DIGITIZED))?.let { return it }
        }
        return inner.firstOrNull { it.type == "CMT1" }?.let { first(it.start, listOf(TAG_DATE_TIME)) }
    }
}
