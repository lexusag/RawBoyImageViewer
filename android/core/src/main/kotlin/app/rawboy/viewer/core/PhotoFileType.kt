package app.rawboy.viewer.core

/**
 * Which files the viewer shows, by extension (case-insensitive).
 * A port of RawBoyBrowseKit's `PhotoFileType.swift`: keep the two in step.
 */
enum class PhotoFileType {
    /** A camera raw. TIFF-based raws (DNG, NEF, ARW...) are raws, not TIFFs. */
    RAW,
    /** A file that is already a picture: JPEG, HEIC, PNG, TIFF... */
    DISPLAY,
    /** A video: shown in the browser with a still as its thumbnail, opened in the default player. */
    VIDEO;

    companion object {
        /** RawBoy's list (`RAW_ACCEPT` in RawBoy's web/src/ui/common/files.ts): keep them the same. */
        val rawExtensions: Set<String> = setOf(
            "3fr", "arw", "cr2", "cr3", "crw", "dcr", "dng", "erf", "fff", "iiq", "kdc", "mos",
            "mrw", "nef", "nrw", "orf", "pef", "raf", "raw", "rw2", "rwl", "sr2", "srf", "srw", "x3f",
        )

        /** RawBoy Browser's image types, plus AVIF, WebP and JPEG XL. */
        val displayExtensions: Set<String> = setOf(
            "avif", "heic", "heif", "jpeg", "jpg", "jxl", "png", "tif", "tiff", "webp",
        )

        /** Common video containers. */
        val videoExtensions: Set<String> = setOf(
            "avi", "m4v", "mkv", "mov", "mp4", "mts", "m2ts", "webm",
        )

        /** MIME types matching RawBoy's Android intent filters. */
        fun mimeTypeFor(fileName: String): String {
            val dot = fileName.lastIndexOf('.')
            if (dot <= 0) return "application/octet-stream"
            return when (fileName.substring(dot + 1).lowercase()) {
                "dng" -> "image/x-adobe-dng"
                "cr2" -> "image/x-canon-cr2"
                "cr3" -> "image/x-canon-cr3"
                "nef" -> "image/x-nikon-nef"
                "nrw" -> "image/x-nikon-nrw"
                "arw" -> "image/x-sony-arw"
                "raf" -> "image/x-fuji-raf"
                "rw2" -> "image/x-panasonic-rw2"
                "orf" -> "image/x-olympus-orf"
                "pef" -> "image/x-pentax-pef"
                "srw" -> "image/x-samsung-srw"
                "jpg", "jpeg" -> "image/jpeg"
                "heic" -> "image/heic"
                "heif" -> "image/heif"
                "png" -> "image/png"
                "tif", "tiff" -> "image/tiff"
                "webp" -> "image/webp"
                "avif" -> "image/avif"
                else -> "image/*"
            }
        }

        /** The type of a file named [fileName], or null when the viewer doesn't show it. */
        fun of(fileName: String): PhotoFileType? {
            val dot = fileName.lastIndexOf('.')
            if (dot <= 0) return null
            val ext = fileName.substring(dot + 1).lowercase()
            return when (ext) {
                in rawExtensions -> RAW
                in displayExtensions -> DISPLAY
                in videoExtensions -> VIDEO
                else -> null
            }
        }
    }
}
