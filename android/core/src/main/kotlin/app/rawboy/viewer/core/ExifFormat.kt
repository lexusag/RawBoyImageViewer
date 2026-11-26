package app.rawboy.viewer.core

import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * EXIF values as the details panel writes them: plain, short, the way photographers say them.
 * A port of RawBoyBrowseKit's `ExifFormat.swift`: keep the two in step.
 */
object ExifFormat {
    private val exifDateFmt = DateTimeFormatter.ofPattern("yyyy:MM:dd HH:mm:ss", Locale.US)

    /** "1/240 s", "1/8 s", "2 s", "1.3 s". */
    fun shutter(seconds: Double): String? {
        if (seconds <= 0.0) return null
        if (seconds >= 1.0) return "${trim(seconds)} s"
        val denominator = 1.0 / seconds
        if (seconds >= 0.3 && abs(denominator - denominator.roundToInt()) > 0.05) {
            return "${trim(seconds)} s"
        }
        return "1/${denominator.roundToInt()} s"
    }

    /** "f/2.8", "f/11". */
    fun aperture(f: Double): String? = if (f > 0.0) "f/${trim(f)}" else null

    /** "ISO 100". */
    fun iso(value: Int): String? = if (value > 0) "ISO $value" else null

    /** "0 EV", "+0.3 EV", "−1.7 EV" (a real minus sign). */
    fun bias(ev: Double): String {
        val rounded = (ev * 10.0).roundToInt() / 10.0
        if (rounded == 0.0) return "0 EV"
        return "${if (rounded > 0) "+" else "−"}${trim(abs(rounded))} EV"
    }

    /** "63 mm", "63 mm (50 mm in 35 mm terms)". */
    fun focalLength(mm: Double?, equivalent35: Double?): String? {
        if (mm == null || mm <= 0.0) return null
        val base = "${trim(mm)} mm"
        if (equivalent35 == null || equivalent35 <= 0.0 || abs(equivalent35 - mm) < 1.0) return base
        return "$base (${trim(equivalent35)} mm in 35 mm terms)"
    }

    fun program(value: Int): String? = when (value) {
        1 -> "Manual"
        2 -> "Program"
        3 -> "Aperture priority"
        4 -> "Shutter priority"
        5 -> "Creative"
        6 -> "Action"
        7 -> "Portrait"
        8 -> "Landscape"
        else -> null
    }

    fun metering(value: Int): String? = when (value) {
        1 -> "Average"
        2 -> "Centre-weighted"
        3 -> "Spot"
        4 -> "Multi-spot"
        5 -> "Multi-segment"
        6 -> "Partial"
        else -> null
    }

    fun flash(value: Int): String {
        val fired = (value and 1) != 0
        return when ((value ushr 3) and 3) {
            2 -> if (fired) "Fired" else "Off"
            3 -> if (fired) "Fired (auto)" else "Did not fire (auto)"
            else -> if (fired) "Fired" else "Did not fire"
        }
    }

    fun whiteBalance(value: Int): String? = when (value) {
        0 -> "Auto"
        1 -> "Manual"
        else -> null
    }

    fun coordinates(latitude: Double, latitudeRef: String?, longitude: Double, longitudeRef: String?): String {
        val lat = String.format(Locale.US, "%.4f", abs(latitude))
        val lon = String.format(Locale.US, "%.4f", abs(longitude))
        val ns = latitudeRef ?: if (latitude < 0) "S" else "N"
        val ew = longitudeRef ?: if (longitude < 0) "W" else "E"
        return "$lat° $ns, $lon° $ew"
    }

    fun camera(make: String?, model: String?): String? {
        val mk = make?.trim()?.ifEmpty { null }
        val md = model?.trim()?.ifEmpty { null }
        if (md == null) return mk
        if (mk == null) return md
        val firstWord = mk.lowercase().substringBefore(' ')
        if (firstWord.isNotEmpty() && md.lowercase().startsWith(firstWord)) return md
        return "$mk $md"
    }

    /** An EXIF date ("2026:03:01 12:23:15") as epoch millis in [zone]. */
    fun dateEpochMillis(exif: String?, zone: ZoneId = ZoneId.systemDefault()): Long? {
        val text = PhotoOrder.validDate(exif) ?: return null
        return runCatching { LocalDateTime.parse(text, exifDateFmt).atZone(zone).toInstant().toEpochMilli() }.getOrNull()
    }

    /** Human-readable file size ("24.3 MB", "820 KB"). */
    fun fileSize(bytes: Long): String {
        if (bytes < 1024L) return "$bytes B"
        val kb = bytes / 1024.0
        if (kb < 1024.0) return String.format(Locale.US, "%.0f KB", kb)
        val mb = kb / 1024.0
        if (mb < 1024.0) return String.format(Locale.US, "%.1f MB", mb)
        return String.format(Locale.US, "%.2f GB", mb / 1024.0)
    }

    internal fun trim(value: Double): String {
        var text = String.format(Locale.US, "%.2f", value)
        while (text.endsWith('0')) text = text.dropLast(1)
        if (text.endsWith('.')) text = text.dropLast(1)
        return text
    }
}
