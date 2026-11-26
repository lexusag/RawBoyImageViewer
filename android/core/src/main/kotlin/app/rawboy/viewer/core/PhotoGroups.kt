package app.rawboy.viewer.core

/**
 * Natural order comparator: case-insensitive, runs of digits compared numerically ("IMG_9" before "IMG_10").
 */
object NaturalOrder : Comparator<String> {
    override fun compare(a: String, b: String): Int {
        val primary = compareNatural(a, b, ignoreCase = true)
        return if (primary != 0) primary else a.compareTo(b)
    }

    private fun compareNatural(a: String, b: String, ignoreCase: Boolean): Int {
        var i = 0
        var j = 0
        while (i < a.length && j < b.length) {
            val ca = a[i]
            val cb = b[j]
            if (ca.isAsciiDigit() && cb.isAsciiDigit()) {
                val startA = i
                while (i < a.length && a[i].isAsciiDigit()) i++
                val startB = j
                while (j < b.length && b[j].isAsciiDigit()) j++

                var nzA = startA
                while (nzA < i - 1 && a[nzA] == '0') nzA++
                var nzB = startB
                while (nzB < j - 1 && b[nzB] == '0') nzB++

                val lenA = i - nzA
                val lenB = j - nzB
                if (lenA != lenB) return lenA.compareTo(lenB)
                for (k in 0 until lenA) {
                    val d = a[nzA + k].compareTo(b[nzB + k])
                    if (d != 0) return d
                }
                val rawLen = (i - startA).compareTo(j - startB)
                if (rawLen != 0) return rawLen
            } else {
                val la = if (ignoreCase) ca.lowercaseChar() else ca
                val lb = if (ignoreCase) cb.lowercaseChar() else cb
                if (la != lb) return la.compareTo(lb)
                i++
                j++
            }
        }
        return a.length.compareTo(b.length)
    }
}

private fun Char.isAsciiDigit(): Boolean = this in '0'..'9'

/**
 * One photo of a folder: its files sharing a base name (a RAW + JPEG pair is one photo) and their sidecars.
 * A port of RawBoyBrowseKit's `PhotoGroups.swift`: keep the two in step.
 */
data class PhotoGroup(
    val stem: String,
    val main: String,
    val companions: List<String>,
    val sidecars: List<String>,
)

object PhotoGroups {
    /** [name] without its last extension ("IMG_1.CR2.xmp" -> "IMG_1.CR2"). A leading dot is not an extension. */
    fun stem(name: String): String {
        val dot = name.lastIndexOf('.')
        return if (dot <= 0) name else name.substring(0, dot)
    }

    fun isRaw(name: String): Boolean = PhotoFileType.of(name) == PhotoFileType.RAW
    fun isPhoto(name: String): Boolean = PhotoFileType.of(name) != null
    fun isSidecar(name: String): Boolean {
        val dot = name.lastIndexOf('.')
        return dot > 0 && name.substring(dot + 1).equals("xmp", ignoreCase = true)
    }

    /**
     * Groups a folder's file names into photos, in natural name order; other files are ignored. Names compare
     * case-insensitively.
     */
    fun group(names: List<String>): List<PhotoGroup> {
        val photos = names.filter(::isPhoto)
        val photoNames = photos.mapTo(HashSet()) { it.lowercase() }
        val byStem = LinkedHashMap<String, MutableList<String>>()
        for (name in photos) {
            byStem.getOrPut(stem(name).lowercase()) { ArrayList() }.add(name)
        }

        val sidecars = HashMap<String, MutableList<String>>()
        for (name in names) {
            if (!isSidecar(name)) continue
            val inner = stem(name)
            var key = (if (isPhoto(inner)) stem(inner) else inner).lowercase()
            val dup = duplicateParts(inner)
            if (dup != null && inner.lowercase() !in photoNames && (dup.first + dup.second).lowercase() in photoNames) {
                key = stem(dup.first + dup.second).lowercase()
            }
            sidecars.getOrPut(key) { ArrayList() }.add(name)
        }

        fun rank(name: String): Int = when (PhotoFileType.of(name)) {
            PhotoFileType.RAW -> 0
            PhotoFileType.VIDEO -> 2
            else -> 1
        }

        val groups = byStem.map { (key, files) ->
            val sorted = files.sortedWith { a, b ->
                val r = rank(a).compareTo(rank(b))
                if (r != 0) r else NaturalOrder.compare(a, b)
            }
            PhotoGroup(
                stem = stem(sorted[0]),
                main = sorted[0],
                companions = sorted.drop(1),
                sidecars = sidecars[key].orEmpty().sorted(),
            )
        }
        return groups.sortedWith { a, b -> NaturalOrder.compare(a.main, b.main) }
    }

    /** [name] with [suffix] after the photo's [stem]. */
    fun withSuffix(name: String, stem: String, suffix: String): String {
        if (name.lowercase().startsWith(stem.lowercase())) {
            return name.substring(0, stem.length) + suffix + name.substring(stem.length)
        }
        val own = stem(name)
        return own + suffix + name.substring(own.length)
    }

    /**
     * Which sidecar file names should be written when saving ratings for [group]:
     * every existing sidecar (NAME.xmp, NAME.EXT.xmp, darktable duplicates), or NAME.xmp when none exist.
     */
    fun sidecarNamesToWrite(group: PhotoGroup): List<String> =
        if (group.sidecars.isNotEmpty()) group.sidecars else listOf("${group.stem}.xmp")

    internal fun duplicateParts(name: String): Pair<String, String>? {
        val dot = name.lastIndexOf('.')
        if (dot <= 0) return null
        val ext = name.substring(dot)
        if (ext.length <= 1 || '.' in ext.substring(1)) return null
        val head = name.substring(0, dot)
        val underscore = head.lastIndexOf('_')
        if (underscore < 0) return null
        val digits = head.substring(underscore + 1)
        if (digits.isEmpty() || !digits.all { it.isAsciiDigit() }) return null
        return head.substring(0, underscore) to ext
    }
}
