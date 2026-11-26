package app.rawboy.viewer.core

import kotlin.math.roundToInt

class XmpWriteException(message: String) : Exception(message)

/**
 * Ratings, orientation and RawBoy's edits in XMP sidecars, as Lightroom, Capture One and darktable read them:
 * xmp:Rating 0-5 stars, -1 = rejected. Picks live in RawBoy's namespace (`rawboy:Pick="1"`), with its edits
 * (`rawboy:Develop`) and Auto settings (`rawboy:Auto`).
 *
 * Existing sidecars usually hold another app's edits: only RawBoy's fields are changed, in place, and everything
 * else is kept byte for byte. A port of RawBoyBrowseKit's `XmpSidecar.swift`: keep the two in step.
 */
object XmpSidecar {
    private const val XMP_NS = "http://ns.adobe.com/xap/1.0/"
    private const val RAWBOY_NS = "http://ns.rawboy.app/1.0/"
    private const val TIFF_NS = "http://ns.adobe.com/tiff/1.0/"

    private const val EMPTY =
        "<?xpacket begin=\"\uFEFF\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n" +
            "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\" x:xmptk=\"RawBoy\">\n" +
            " <rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\n" +
            "  <rdf:Description rdf:about=\"\"/>\n" +
            " </rdf:RDF>\n" +
            "</x:xmpmeta>\n" +
            "<?xpacket end=\"w\"?>\n"

    fun readRating(text: String): Rating = read(text)

    fun writeRating(text: String?, rating: Rating): String = write(text, rating)

    fun read(text: String): Rating {
        val rating = fieldValue(text, "xmp:Rating")?.toDoubleOrNull() ?: 0.0
        val pick = fieldValue(text, "rawboy:Pick") == "1"
        if (rating < 0) return Rating(stars = 0, flag = Flag.REJECT)
        return Rating(stars = rating.roundToInt().coerceIn(0, 5), flag = if (pick) Flag.PICK else null)
    }

    fun hasRating(text: String): Boolean =
        "xmp:Rating" in text || "rawboy:Pick" in text

    fun write(text: String?, rating: Rating): String {
        var out = text ?: EMPTY
        out = setField(out, "xmp:Rating", "xmp", XMP_NS, (if (rating.flag == Flag.REJECT) -1 else rating.stars).toString())
        out = setField(out, "rawboy:Pick", "rawboy", RAWBOY_NS, if (rating.flag == Flag.PICK) "1" else null)
        return out
    }

    fun readOrientation(text: String): Int? =
        fieldValue(text, "tiff:Orientation")?.toIntOrNull()?.takeIf { it in 1..8 }

    fun writeOrientation(text: String?, orientation: Int?): String =
        setField(text ?: EMPTY, "tiff:Orientation", "tiff", TIFF_NS, orientation?.toString())

    fun readAuto(text: String): String? =
        fieldValue(text, "rawboy:Auto")?.takeIf { it.isNotEmpty() }?.let(::unescapeXml)

    fun writeAuto(text: String?, json: String?): String =
        setField(text ?: EMPTY, "rawboy:Auto", "rawboy", RAWBOY_NS, json?.let(::escapeXml))

    fun readDevelop(text: String): String? =
        fieldValue(text, "rawboy:Develop")?.takeIf { it.isNotEmpty() }?.let(::unescapeXml)

    fun writeDevelop(text: String?, json: String?): String =
        setField(text ?: EMPTY, "rawboy:Develop", "rawboy", RAWBOY_NS, json?.let(::escapeXml))

    private fun attributeRe(name: String): Regex =
        Regex("""(\s${Regex.escape(name)}\s*=\s*)(["'])((?:(?!\2)[^<])*)\2""")

    private fun elementRe(name: String): Regex =
        Regex("(<${Regex.escape(name)}>)([^<]*)(</${Regex.escape(name)}>)")

    private fun fieldValue(text: String, name: String): String? {
        attributeRe(name).find(text)?.let { return it.groupValues[3].trim() }
        elementRe(name).find(text)?.let { return it.groupValues[2].trim() }
        return null
    }

    private fun setField(text: String, name: String, prefix: String, ns: String, value: String?): String {
        attributeRe(name).find(text)?.let { m ->
            if (value == null) return text.removeRange(m.range)
            val valGroup = m.groups[3]!!
            return text.replaceRange(valGroup.range, value)
        }
        elementRe(name).find(text)?.let { m ->
            if (value != null) {
                val valGroup = m.groups[2]!!
                return text.replaceRange(valGroup.range, value)
            }
            val whole = Regex("""\s*<${Regex.escape(name)}>[^<]*</${Regex.escape(name)}>""").find(text)
                ?: return text
            return text.removeRange(whole.range)
        }
        if (value == null) return text
        val descriptionRe = Regex("""<rdf:Description\b[^>]*?(?=/?>)""")
        val d = descriptionRe.find(text) ?: throw XmpWriteException("No rdf:Description in sidecar")
        val description = d.value
        val declared = Regex("""\sxmlns:${Regex.escape(prefix)}\s*=""").containsMatchIn(description)
        val added = (if (declared) "" else "\n   xmlns:$prefix=\"$ns\"") + "\n   $name=\"$value\""
        val insertAt = d.range.last + 1
        return text.substring(0, insertAt) + added + text.substring(insertAt)
    }

    internal fun escapeXml(s: String): String = s
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
        .replace("'", "&apos;")

    internal fun unescapeXml(s: String): String {
        if ('&' !in s) return s
        val out = StringBuilder(s.length)
        var i = 0
        while (i < s.length) {
            val amp = s.indexOf('&', i)
            if (amp < 0) {
                out.append(s, i, s.length)
                break
            }
            out.append(s, i, amp)
            val semi = s.indexOf(';', amp + 1)
            if (semi < 0) {
                out.append(s, amp, s.length)
                break
            }
            val entity = s.substring(amp + 1, semi)
            when (entity.lowercase()) {
                "amp" -> out.append('&')
                "lt" -> out.append('<')
                "gt" -> out.append('>')
                "quot" -> out.append('"')
                "apos" -> out.append('\'')
                else -> {
                    val code = when {
                        entity.startsWith("#x", ignoreCase = true) -> entity.substring(2).toIntOrNull(16)
                        entity.startsWith("#") -> entity.substring(1).toIntOrNull(10)
                        else -> null
                    }
                    if (code != null && Character.isValidCodePoint(code)) {
                        out.appendCodePoint(code)
                    } else {
                        out.append(s, amp, semi + 1)
                    }
                }
            }
            i = semi + 1
        }
        return out.toString()
    }
}
