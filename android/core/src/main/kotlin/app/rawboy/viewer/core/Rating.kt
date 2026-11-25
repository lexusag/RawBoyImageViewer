package app.rawboy.viewer.core

/**
 * Pick or reject: RawBoy Browser's flags.
 * A port of RawBoyBrowseKit's `Rating.swift`: keep the two in step.
 */
enum class Flag(val raw: String, val dbValue: Int) {
    PICK("pick", 1),
    REJECT("reject", -1);

    companion object {
        fun fromRaw(raw: String?): Flag? = entries.firstOrNull { it.raw == raw }
        fun fromDb(value: Int): Flag? = when (value) {
            1 -> PICK
            -1 -> REJECT
            else -> null
        }
    }
}

/** A photo's stars and flag, as RawBoy Browser keeps them (`XmpSidecar.ts`). */
data class Rating(
    val stars: Int = 0,
    val flag: Flag? = null,
) {
    val isRated: Boolean get() = stars > 0 || flag != null

    companion object {
        val NONE = Rating()

        /** [ratings] after [stars] is given to them all: same number clears, stars clear reject. */
        fun withStars(ratings: List<Rating>, stars: Int): List<Rating> {
            val clear = ratings.all { it.stars == stars }
            return ratings.map {
                Rating(stars = if (clear) 0 else stars, flag = if (it.flag == Flag.REJECT) null else it.flag)
            }
        }

        /** [ratings] after [flag] is toggled on them all: set on each, or cleared when every one already has it. */
        fun withFlag(ratings: List<Rating>, flag: Flag): List<Rating> {
            val clear = ratings.all { it.flag == flag }
            return ratings.map { Rating(stars = it.stars, flag = if (clear) null else flag) }
        }
    }
}

/** Which photos the grid shows, by flag, with at least some stars. */
enum class FlagFilter(val raw: String) {
    ALL("all"),
    PICKS("picks"),
    UNFLAGGED("unflagged"),
    REJECTS("rejects");

    fun passes(rating: Rating, minStars: Int): Boolean {
        val flagOk = when (this) {
            ALL -> true
            PICKS -> rating.flag == Flag.PICK
            UNFLAGGED -> rating.flag == null
            REJECTS -> rating.flag == Flag.REJECT
        }
        return flagOk && rating.stars >= minStars
    }

    companion object {
        fun counts(ratings: List<Rating>): Map<FlagFilter, Int> {
            var picks = 0
            var unflagged = 0
            var rejects = 0
            for (r in ratings) {
                when (r.flag) {
                    Flag.PICK -> picks++
                    Flag.REJECT -> rejects++
                    null -> unflagged++
                }
            }
            return mapOf(
                ALL to ratings.size,
                PICKS to picks,
                UNFLAGGED to unflagged,
                REJECTS to rejects,
            )
        }
    }
}
