package app.rawboy.viewer.core

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * How the browser orders photos: by when they were shot, or by file name.
 * A port of RawBoyBrowseKit's `PhotoOrder.swift`: keep the two in step.
 */
enum class PhotoSort(val raw: String) {
    DATE("date"),
    NAME("name");

    companion object {
        fun fromRaw(raw: String?): PhotoSort = entries.firstOrNull { it.raw == raw } ?: DATE
    }
}

object PhotoOrder {
    private val validDateRe = Regex("^\\d{4}:\\d\\d:\\d\\d \\d\\d:\\d\\d:\\d\\d")
    private val exifFormatter = DateTimeFormatter.ofPattern("yyyy:MM:dd HH:mm:ss")

    /** [text] as an EXIF date "YYYY:MM:DD HH:MM:SS" (sorts as text) if it is one, else null. */
    fun validDate(text: String?): String? {
        val t = text?.trim { it.isWhitespace() || it == '\u0000' } ?: return null
        if (!validDateRe.containsMatchIn(t) || t.startsWith("0000")) return null
        return t.substring(0, 19)
    }

    /** A file's modified date (epoch millis) as an EXIF date in [zone]. */
    fun fileDate(epochMillis: Long?, zone: ZoneId = ZoneId.systemDefault()): String? {
        if (epochMillis == null || epochMillis <= 0L) return null
        return Instant.ofEpochMilli(epochMillis).atZone(zone).format(exifFormatter)
    }

    /** File names as people read them: case-insensitive, runs of digits by value. */
    fun compareNames(a: String, b: String): Int = NaturalOrder.compare(a, b)

    /** Whether [a] goes before [b] for [sort]. */
    fun inOrder(sort: PhotoSort, a: Pair<String?, String>, b: Pair<String?, String>): Boolean {
        val byDate = when {
            a.first != null && b.first != null -> a.first!!.compareTo(b.first!!)
            a.first == null && b.first == null -> 0
            a.first == null -> 1
            else -> -1
        }
        val byName = compareNames(a.second, b.second)
        val first = if (sort == PhotoSort.DATE) byDate else byName
        val second = if (sort == PhotoSort.DATE) byName else byDate
        return (if (first != 0) first else second) < 0
    }

    fun comparator(sort: PhotoSort): Comparator<Pair<String?, String>> = Comparator { a, b ->
        when {
            inOrder(sort, a, b) -> -1
            inOrder(sort, b, a) -> 1
            else -> 0
        }
    }

    /** The photo to show when [previous] (at [index], [current]) becomes [remaining]. */
    fun nextAfterRemoval(previous: List<String>, remaining: List<String>, current: String?, index: Int): String? {
        if (remaining.isEmpty()) return null
        val kept = remaining.toHashSet()
        if (current != null && current in kept) return current
        if (index in previous.indices) {
            for (i in index until previous.size) if (previous[i] in kept) return previous[i]
            for (i in index - 1 downTo 0) if (previous[i] in kept) return previous[i]
        }
        return remaining[index.coerceIn(0, remaining.lastIndex)]
    }
}
