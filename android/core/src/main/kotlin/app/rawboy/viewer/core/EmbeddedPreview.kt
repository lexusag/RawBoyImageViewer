package app.rawboy.viewer.core

/**
 * The JPEG preview a camera embedded in its raw file, found without decoding the raw, so a folder of raws opens in
 * seconds. A port of RawBoyBrowseKit's `EmbeddedPreview.swift`: keep the two in step.
 */
data class EmbeddedPreview(
    val offset: Int,
    val length: Int,
    val width: Int,
    val height: Int,
    val jpegOrientation: Int,
    val rawOrientation: Int,
) {
    /**
     * The JPEG's bytes, with an EXIF orientation added when the raw's orientation applies (the JPEG's own wins:
     * Fujifilm's carries one), so decoders show it upright.
     */
    fun jpeg(source: ByteSource): ByteArray {
        val bytes = source.read(offset, length)
        return if (jpegOrientation == 0 && rawOrientation > 1) {
            EmbeddedPreviews.withOrientation(bytes, rawOrientation)
        } else {
            bytes
        }
    }
}

object EmbeddedPreviews {
    data class Candidate(val offset: Int, val length: Int)

    internal data class JpegInfo(val width: Int, val height: Int, val orientation: Int)

    data class Box(val type: String, val start: Int, val end: Int, val uuid: String)

    /** How much of a file's start the fallback scan reads (2 MB on mobile to avoid OOM). */
    private const val SCAN_BYTES = 2 shl 20

    private const val TAG_ORIENTATION = 274
    private const val TAG_COMPRESSION = 259
    private const val TAG_STRIP_OFFSETS = 273
    private const val TAG_STRIP_BYTE_COUNTS = 279
    private const val TAG_SUB_IFDS = 330
    private const val TAG_JPEG_OFFSET = 513
    private const val TAG_JPEG_LENGTH = 514
    private const val TAG_RW2_JPEG = 0x2e

    internal const val CANON_UUID = "85c0b687820f11e08111f4ce462b6a48"
    private const val CANON_PREVIEW_UUID = "eaf42b5e1c984b88b9fbb7dc406e4d16"

    private val typeSize = mapOf(
        1 to 1, 2 to 1, 3 to 2, 4 to 4, 5 to 8, 6 to 1, 7 to 1,
        8 to 2, 9 to 4, 10 to 8, 11 to 4, 12 to 8, 13 to 4,
    )

    /** The largest embedded preview of [source], or null if there is none. */
    fun find(source: ByteSource): EmbeddedPreview? {
        val head = source.read(0, 16)
        var candidates: List<Candidate> = emptyList()
        var orientation = 0
        when {
            head.ascii(0, 15) == "FUJIFILMCCD-RAW" -> {
                val v = source.read(84, 8)
                candidates = listOf(Candidate(v.u32(0, false), v.u32(4, false)))
            }
            head.ascii(4, 8) == "ftyp" -> {
                val res = cr3Candidates(source)
                candidates = res.first
                orientation = res.second
            }
            isTiff(head) -> {
                val res = tiffCandidates(source, base = 0)
                candidates = res.first
                orientation = res.second
            }
        }
        var best = largest(source, candidates)
        if (best == null) {
            best = largest(source, scanForJpegs(source.read(0, SCAN_BYTES)))
        }
        val (candidate, info) = best ?: return null
        return EmbeddedPreview(
            offset = candidate.offset,
            length = candidate.length,
            width = info.width,
            height = info.height,
            jpegOrientation = info.orientation,
            rawOrientation = orientation,
        )
    }

    /** The raw file's own EXIF orientation (TIFF IFD0 or CR3 CMT1), or 0 if absent. */
    fun rawOrientation(source: ByteSource): Int {
        val head = source.read(0, 16)
        return when {
            isTiff(head) -> tiffCandidates(source, base = 0).second
            head.ascii(4, 8) == "ftyp" -> cr3Candidates(source).second
            else -> 0
        }
    }

    private fun largest(source: ByteSource, candidates: List<Candidate>): Pair<Candidate, JpegInfo>? {
        var best: Pair<Candidate, JpegInfo>? = null
        for (c in candidates) {
            if (c.length < 20 || c.offset < 0 || c.offset.toLong() + c.length.toLong() > source.size.toLong()) continue
            val info = jpegInfo(source, c.offset, c.length) ?: continue
            if (best == null || info.width.toLong() * info.height > best.second.width.toLong() * best.second.height) {
                best = c to info
            }
        }
        return best
    }

    /** II/MM followed by 42, or the magics Olympus (ORF: "RO", "RS") and Panasonic (RW2: 0x55) use instead. */
    fun isTiff(b: ByteArray): Boolean {
        if (b.size < 4) return false
        val le = b.u8(0) == 0x49 && b.u8(1) == 0x49
        val be = b.u8(0) == 0x4d && b.u8(1) == 0x4d
        if (!le && !be) return false
        val magic = b.u16(2, le)
        return magic == 42 || magic == 0x4f52 || magic == 0x5352 || magic == 0x55
    }

    internal fun tiffCandidates(source: ByteSource, base: Int): Pair<List<Candidate>, Int> {
        val header = source.read(base, 8)
        val le = header.u8(0) == 0x49
        val candidates = ArrayList<Candidate>()
        var orientation = 0
        val queue = ArrayDeque<Int>()
        queue.add(header.u32(4, le))
        val seen = HashSet<Int>()
        var first = true

        while (queue.isNotEmpty() && seen.size < 32) {
            val at = queue.removeFirst()
            if (at <= 0 || at in seen || base.toLong() + at.toLong() + 2 > source.size.toLong()) continue
            seen.add(at)
            val n = source.u16(base + at, le)
            if (n <= 0 || n > 1000) continue
            val ifd = source.read(base + at + 2, n * 12 + 4)

            fun values(i: Int, max: Int = 64): List<Int> {
                val p = i * 12
                val type = ifd.u16(p + 2, le)
                val count = ifd.u32(p + 4, le)
                if (type != 3 && type != 4 && type != 13) return emptyList()
                val size = typeSize[type] ?: 1
                val wanted = minOf(count, max)
                if (wanted <= 0) return emptyList()
                val data = if (size.toLong() * count.toLong() <= 4L) {
                    val start = minOf(p + 8, ifd.size)
                    val end = minOf(p + 12, ifd.size)
                    ifd.copyOfRange(start, end)
                } else {
                    source.read(base + ifd.u32(p + 8, le), size * wanted)
                }
                return List(wanted) { k -> if (type == 3) data.u16(k * 2, le) else data.u32(k * 4, le) }
            }

            val tags = HashMap<Int, Int>(n * 2)
            for (i in 0 until n) tags[ifd.u16(i * 12, le)] = i
            fun one(tag: Int): Int? = tags[tag]?.let { values(it).firstOrNull() }

            if (first) orientation = one(TAG_ORIENTATION) ?: 0
            first = false

            val jOff = one(TAG_JPEG_OFFSET)
            val jLen = one(TAG_JPEG_LENGTH)
            if (jOff != null && jLen != null && jOff != 0 && jLen != 0) {
                candidates.add(Candidate(base + jOff, jLen))
            }
            val compression = one(TAG_COMPRESSION)
            if (compression == 6 || compression == 7) {
                val offsets = tags[TAG_STRIP_OFFSETS]?.let { values(it) }.orEmpty()
                val counts = tags[TAG_STRIP_BYTE_COUNTS]?.let { values(it) }.orEmpty()
                if (offsets.size == 1 && counts.size == 1) {
                    candidates.add(Candidate(base + offsets[0], counts[0]))
                }
            }
            tags[TAG_RW2_JPEG]?.let { i ->
                val count = ifd.u32(i * 12 + 4, le)
                if (count > 4) candidates.add(Candidate(base + ifd.u32(i * 12 + 8, le), count))
            }
            tags[TAG_SUB_IFDS]?.let { i -> queue.addAll(values(i)) }
            queue.add(ifd.u32(n * 12, le))
        }
        return candidates to orientation
    }

    /** The boxes of an ISO base media file between [from] and [to]. */
    fun boxes(source: ByteSource, from: Int, to: Int): List<Box> {
        val out = ArrayList<Box>()
        var at = from
        while (at + 8 <= to && out.size < 256) {
            val h = source.read(at, 32)
            if (h.size < 8) break
            var size = h.u32(0, false)
            val type = h.ascii(4, 8)
            var header = 8
            if (size == 1) {
                size = minOf(h.u64be(8), (Int.MAX_VALUE / 2).toLong()).toInt()
                header = 16
            } else if (size == 0) {
                size = to - at
            }
            if (size < header) break
            var uuid = ""
            if (type == "uuid") {
                val sb = StringBuilder(32)
                for (k in header until header + 16) {
                    val v = h.u8(k)
                    sb.append(HEX[(v ushr 4) and 15]).append(HEX[v and 15])
                }
                uuid = sb.toString()
                header += 16
            }
            out.add(Box(type, at + header, minOf(at + size, to), uuid))
            if (size > to - at) break
            at += size
        }
        return out
    }

    private const val HEX = "0123456789abcdef"

    private fun cr3Candidates(source: ByteSource): Pair<List<Candidate>, Int> {
        val candidates = ArrayList<Candidate>()
        var orientation = 0
        val top = boxes(source, 0, source.size)
        val moov = top.firstOrNull { it.type == "moov" }
        if (moov != null) {
            val inner = boxes(source, moov.start, moov.end)
            val canon = inner.firstOrNull { it.type == "uuid" && it.uuid == CANON_UUID }
            if (canon != null) {
                val cmt1 = boxes(source, canon.start, canon.end).firstOrNull { it.type == "CMT1" }
                if (cmt1 != null) orientation = tiffCandidates(source, base = cmt1.start).second
            }
            val trak = inner.firstOrNull { it.type == "trak" }
            val stbl = trak?.let { descend(source, it, listOf("mdia", "minf", "stbl")) }
            if (stbl != null) {
                val parts = boxes(source, stbl.start, stbl.end)
                val stsz = parts.firstOrNull { it.type == "stsz" }
                val co64 = parts.firstOrNull { it.type == "co64" }
                val stco = parts.firstOrNull { it.type == "stco" }
                if (stsz != null && (co64 != null || stco != null)) {
                    val sz = source.read(stsz.start, 16)
                    val length = if (sz.u32(4, false) != 0) sz.u32(4, false) else sz.u32(12, false)
                    val offset = if (co64 != null) {
                        minOf(source.read(co64.start + 8, 8).u64be(0), (Int.MAX_VALUE / 2).toLong()).toInt()
                    } else {
                        source.u32(stco!!.start + 8, false)
                    }
                    candidates.add(Candidate(offset, length))
                }
            }
        }
        val preview = top.firstOrNull { it.type == "uuid" && it.uuid == CANON_PREVIEW_UUID }
        if (preview != null) {
            val prvw = boxes(source, preview.start + 8, preview.end).firstOrNull { it.type == "PRVW" }
            if (prvw != null) {
                candidates.add(Candidate(prvw.start + 16, source.u32(prvw.start + 12, false)))
            }
        }
        return candidates to orientation
    }

    private fun descend(source: ByteSource, box: Box, path: List<String>): Box? {
        var at: Box? = box
        for (type in path) {
            val current = at ?: return null
            at = boxes(source, current.start, current.end).firstOrNull { it.type == type }
        }
        return at
    }

    internal fun jpegInfo(source: ByteSource, offset: Int, length: Int): JpegInfo? {
        val end = offset + length
        if (source.u16(offset, false) != 0xffd8) return null
        var at = offset + 2
        var orientation = 0
        var i = 0
        while (i < 64 && at + 4 <= end) {
            i += 1
            val m = source.read(at, 4)
            if (m.size != 4 || m.u8(0) != 0xff) return null
            val marker = m.u8(1)
            if (marker == 0xff) {
                at += 1
                continue
            }
            val size = m.u16(2, false)
            if (marker == 0xc0 || marker == 0xc1 || marker == 0xc2) {
                val f = source.read(at + 4, 5)
                val height = f.u16(1, false)
                val width = f.u16(3, false)
                return if (width > 0 && height > 0) JpegInfo(width, height, orientation) else null
            }
            if ((marker in 0xc3..0xcf && marker != 0xc4 && marker != 0xc8 && marker != 0xcc) || marker == 0xda) {
                return null
            }
            if (marker == 0xe1 && orientation == 0 && size > 16) {
                val app1 = source.read(at + 4, minOf(size, 4096) - 2)
                if (app1.ascii(0, 4) == "Exif" && app1.size > 6) {
                    orientation = tiffOrientation(app1.copyOfRange(6, app1.size))
                }
            }
            at += 2 + size
        }
        return null
    }

    /** IFD0's Orientation in the TIFF bytes [b] (an EXIF payload), 0 if absent. */
    fun tiffOrientation(b: ByteArray): Int {
        if (b.size < 8 || !isTiff(b)) return 0
        val le = b.u8(0) == 0x49
        val ifd = b.u32(4, le)
        if (ifd < 0 || ifd + 2 > b.size) return 0
        val n = b.u16(ifd, le)
        var i = 0
        while (i < n && ifd + 2 + i * 12 + 12 <= b.size) {
            val p = ifd + 2 + i * 12
            if (b.u16(p, le) == TAG_ORIENTATION) return b.u16(p + 8, le)
            i += 1
        }
        return 0
    }

    /** Complete baseline/progressive JPEG streams in [b]. */
    fun scanForJpegs(b: ByteArray): List<Candidate> {
        val found = ArrayList<Candidate>()
        var i = 0
        while (i + 4 < b.size && found.size < 16) {
            if (b.u8(i) != 0xff || b.u8(i + 1) != 0xd8 || b.u8(i + 2) != 0xff) {
                i += 1
                continue
            }
            val end = jpegEnd(b, i)
            if (end > 0) {
                found.add(Candidate(i, end - i))
                i = end
            } else {
                i += 2
            }
        }
        return found
    }

    private fun jpegEnd(b: ByteArray, start: Int): Int {
        var at = start + 2
        var frame = false
        while (at + 4 <= b.size) {
            if (b.u8(at) != 0xff) return -1
            val marker = b.u8(at + 1)
            if (marker == 0xff) {
                at += 1
                continue
            }
            val size = b.u16(at + 2, false)
            if (marker == 0xc0 || marker == 0xc1 || marker == 0xc2) {
                frame = true
            } else if (marker in 0xc3..0xcf && marker != 0xc4 && marker != 0xc8 && marker != 0xcc) {
                return -1
            }
            at += 2 + size
            if (marker != 0xda) continue
            if (!frame) return -1
            while (at + 1 < b.size) {
                if (b.u8(at) != 0xff) {
                    at += 1
                    continue
                }
                val next = b.u8(at + 1)
                if (next == 0x00 || next in 0xd0..0xd7 || next == 0xff) {
                    at += if (next == 0xff) 1 else 2
                    continue
                }
                if (next == 0xd9) return at + 2
                break
            }
        }
        return -1
    }

    /** [jpeg] with an APP1 EXIF segment holding only [orientation] inserted after SOI. */
    fun withOrientation(jpeg: ByteArray, orientation: Int): ByteArray {
        val app1 = byteArrayOf(
            0xff.toByte(), 0xe1.toByte(), 0x00, 0x22,
            0x45, 0x78, 0x69, 0x66, 0x00, 0x00,
            0x4d, 0x4d, 0x00, 0x2a, 0x00, 0x00, 0x00, 0x08,
            0x00, 0x01,
            0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, (orientation and 0xff).toByte(), 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
        )
        if (jpeg.size < 2) return jpeg
        val out = ByteArray(jpeg.size + app1.size)
        out[0] = jpeg[0]
        out[1] = jpeg[1]
        System.arraycopy(app1, 0, out, 2, app1.size)
        System.arraycopy(jpeg, 2, out, 2 + app1.size, jpeg.size - 2)
        return out
    }
}
