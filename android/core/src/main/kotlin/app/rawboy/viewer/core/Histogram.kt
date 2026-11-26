package app.rawboy.viewer.core

import kotlin.math.roundToInt

/**
 * A photo's red, green and blue levels, with the share of clipped highlights and crushed shadows.
 * A port of RawBoyBrowseKit's `Histogram.swift`: keep the two in step.
 */
class Histogram(
    val red: IntArray,
    val green: IntArray,
    val blue: IntArray,
    val highlights: Double,
    val shadows: Double,
    val peak: Int,
) {
    companion object {
        const val BINS = 64
        const val CLIP_SHOWN = 0.001

        /** Computes a histogram from Android ARGB_8888 pixels. */
        fun fromArgb(pixels: IntArray): Histogram {
            val r = IntArray(BINS)
            val g = IntArray(BINS)
            val b = IntArray(BINS)
            var high = 0
            var low = 0
            for (px in pixels) {
                val pr = (px ushr 16) and 0xFF
                val pg = (px ushr 8) and 0xFF
                val pb = px and 0xFF
                r[pr * BINS / 256]++
                g[pg * BINS / 256]++
                b[pb * BINS / 256]++
                val m = maxOf(pr, pg, pb)
                if (m >= 255) high++ else if (m <= 1) low++
            }
            val n = maxOf(1, pixels.size).toDouble()
            fun innerMax(a: IntArray): Int {
                var mx = 0
                for (i in 1 until BINS - 1) if (a[i] > mx) mx = a[i]
                return mx
            }
            val peak = maxOf(1, innerMax(r), innerMax(g), innerMax(b))
            return Histogram(r, g, b, high / n, low / n, peak)
        }

        fun percent(f: Double): String {
            if (f >= 0.1) return "${(f * 100.0).roundToInt()}%"
            if (f > 0.0 && f < 0.001) return "<0.1%"
            val tenths = (f * 1000.0).roundToInt() / 10.0
            return "$tenths%"
        }
    }
}
