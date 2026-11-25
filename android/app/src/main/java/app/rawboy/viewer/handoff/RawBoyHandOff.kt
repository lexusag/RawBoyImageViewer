package app.rawboy.viewer.handoff

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import app.rawboy.viewer.core.PhotoFileType
import app.rawboy.viewer.data.BatchDao
import app.rawboy.viewer.data.BatchEntity
import app.rawboy.viewer.data.BatchItemEntity
import app.rawboy.viewer.data.PhotoWithCull
import app.rawboy.viewer.sources.PhotoSource

enum class AutoImportMode(val raw: String, val label: String) {
    LOOKS("looks", "Looks"),
    FILM("film", "Film"),
    AS_IS("asis", "As is");

    companion object {
        fun fromRaw(raw: String): AutoImportMode = entries.firstOrNull { it.raw == raw } ?: LOOKS
    }
}

/**
 * Hand-off to the real Android RawBoy apps (`lexusag/RawBoy`):
 * - RawBoy Pro (`app.rawboy`): accepts `ACTION_VIEW` / `ACTION_SEND` for one photo.
 * - RawBoy Auto (`app.rawboy.auto`): accepts `ACTION_SEND` and `ACTION_SEND_MULTIPLE` with `EXTRA_STREAM`
 *   for a batch of raws, JPEGs, HEICs, PNGs, TIFFs.
 *
 * Uses `ClipData` + `FLAG_GRANT_READ_URI_PERMISSION` so RawBoy reads SAF URIs directly without copying.
 */
class RawBoyHandOff(
    private val context: Context,
    private val batchDao: BatchDao,
) {
    fun isRawBoyInstalled(): Boolean = isInstalled(PKG_RAWBOY)
    fun isRawBoyAutoInstalled(): Boolean = isInstalled(PKG_RAWBOY_AUTO)

    /** Collects URIs to send: raws by default, plus paired JPEGs when [includeJpegs] is true. */
    fun collectUris(source: PhotoSource, photos: List<PhotoWithCull>, includeJpegs: Boolean): List<Pair<Uri, String>> {
        val out = ArrayList<Pair<Uri, String>>(photos.size)
        for (p in photos) {
            out.add(source.uriForShare(p.docId) to PhotoFileType.mimeTypeFor(p.relPath))
            if (includeJpegs && p.companionDocIds.isNotEmpty()) {
                val names = p.companionNames.split('\n')
                val ids = p.companionDocIds.split('\n')
                for (i in ids.indices) {
                    val id = ids[i]
                    val name = names.getOrNull(i) ?: continue
                    if (id.isNotEmpty() && PhotoFileType.of(name) == PhotoFileType.DISPLAY) {
                        out.add(source.uriForShare(id) to PhotoFileType.mimeTypeFor(name))
                    }
                }
            }
        }
        return out
    }

    /** Sends the first photo to RawBoy Pro (`app.rawboy`), matching Mac's Send to RawBoy Pro behaviour. */
    suspend fun sendToRawBoy(source: PhotoSource, photos: List<PhotoWithCull>): Boolean {
        val first = photos.firstOrNull() ?: return false
        val uri = source.uriForShare(first.docId)
        val mime = PhotoFileType.mimeTypeFor(first.relPath)
        val intent = Intent(Intent.ACTION_SEND).apply {
            setPackage(PKG_RAWBOY)
            type = mime
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newRawUri("photo", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val launched = launchIntent(intent)
        if (launched) recordBatch("rawboy", "edit", listOf(first))
        return launched
    }

    /** Sends [photos] as a batch to RawBoy Auto (`app.rawboy.auto`). */
    suspend fun sendToRawBoyAuto(
        source: PhotoSource,
        photos: List<PhotoWithCull>,
        mode: AutoImportMode,
        includeJpegs: Boolean,
    ): Boolean {
        val items = collectUris(source, photos, includeJpegs)
        if (items.isEmpty()) return false
        val uris = ArrayList<Uri>(items.map { it.first })
        val mime = if (items.map { it.second }.distinct().size == 1) items[0].second else "image/*"

        val intent = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).apply {
                setPackage(PKG_RAWBOY_AUTO)
                type = mime
                putExtra(Intent.EXTRA_STREAM, uris[0])
                putExtra(EXTRA_IMPORT_MODE, mode.raw)
                clipData = ClipData.newRawUri("photo", uris[0])
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                setPackage(PKG_RAWBOY_AUTO)
                type = mime
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                putExtra(EXTRA_IMPORT_MODE, mode.raw)
                clipData = buildClipData(uris)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        }
        val launched = launchIntent(intent)
        if (launched) recordBatch("rawboy_auto", mode.raw, photos)
        return launched
    }

    /** Generic system Share sheet fallback when RawBoy is not installed. */
    suspend fun shareSystem(source: PhotoSource, photos: List<PhotoWithCull>, includeJpegs: Boolean): Boolean {
        val items = collectUris(source, photos, includeJpegs)
        if (items.isEmpty()) return false
        val uris = ArrayList<Uri>(items.map { it.first })
        val base = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).apply {
                type = items[0].second
                putExtra(Intent.EXTRA_STREAM, uris[0])
                clipData = ClipData.newRawUri("photo", uris[0])
            }
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                type = "image/*"
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                clipData = buildClipData(uris)
            }
        }.apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val chooser = Intent.createChooser(base, "Share photos").apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val launched = launchIntent(chooser)
        if (launched) recordBatch("share", "share", photos)
        return launched
    }

    private fun buildClipData(uris: List<Uri>): ClipData {
        val clip = ClipData.newRawUri("photos", uris.first())
        for (i in 1 until uris.size) clip.addItem(ClipData.Item(uris[i]))
        return clip
    }

    private fun launchIntent(intent: Intent): Boolean =
        runCatching {
            context.startActivity(intent)
            true
        }.getOrDefault(false)

    @Suppress("DEPRECATION")
    private fun isInstalled(pkg: String): Boolean =
        runCatching {
            if (android.os.Build.VERSION.SDK_INT >= 33) {
                context.packageManager.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0))
            } else {
                context.packageManager.getPackageInfo(pkg, 0)
            }
            true
        }.getOrDefault(false)

    private suspend fun recordBatch(target: String, mode: String, photos: List<PhotoWithCull>) {
        val batchId = batchDao.insertBatch(BatchEntity(target = target, mode = mode))
        batchDao.insertItems(photos.map { BatchItemEntity(batchId = batchId, photoId = it.id) })
    }

    companion object {
        const val PKG_RAWBOY = "app.rawboy"
        const val PKG_RAWBOY_AUTO = "app.rawboy.auto"
        const val EXTRA_IMPORT_MODE = "app.rawboy.extra.IMPORT_MODE"
    }
}
