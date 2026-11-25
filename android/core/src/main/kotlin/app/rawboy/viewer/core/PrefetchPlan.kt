package app.rawboy.viewer.core

/**
 * Which neighbours of the current photo to load ahead, nearest first.
 * A port of RawBoyBrowseKit's `PrefetchPlan.swift`: keep the two in step.
 */
object PrefetchPlan {
    fun order(current: Int, count: Int, forward: Boolean, ahead: Int = 3, behind: Int = 1): List<Int> {
        val step = if (forward) 1 else -1
        val out = ArrayList<Int>(ahead + behind)
        for (i in 1..ahead) {
            val idx = current + i * step
            if (idx in 0 until count && idx != current) out.add(idx)
        }
        for (i in 1..behind) {
            val idx = current - i * step
            if (idx in 0 until count && idx != current) out.add(idx)
        }
        return out
    }
}
