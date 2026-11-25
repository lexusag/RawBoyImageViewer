package app.rawboy.viewer.imaging

import android.app.ActivityManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import androidx.exifinterface.media.ExifInterface
import app.rawboy.viewer.core.EmbeddedPreviews
import app.rawboy.viewer.core.ExifFormat
import app.rawboy.viewer.core.Histogram
import app.rawboy.viewer.core.LRUCache
import app.rawboy.viewer.core.PhotoFileType
import app.rawboy.viewer.data.PhotoWithCull
import app.rawboy.viewer.sources.PhotoSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

data class PhotoDetails(
    val camera: String?,
    val lens: String?,
    val exposure: String?,
    val focalLength: String?,
    val date: String?,
    val dimensions: String?,
    val fileSize: String,
    val histogram: Histogram?,
)

/**
 * Loads grid thumbnails (cached on disk) and viewer previews (cached in a device-sized memory LRU).
 * Uses `EmbeddedPreviews.find` first for raws so folders of 1,000+ 50 MP raws open smoothly without OOM.
 */
class ImageRepository(private val context: Context) {
    private val thumbDir = File(context.cacheDir, "thumbnails").apply { mkdirs() }

    private val thumbCache = LRUCache<String, Bitmap>(budget = minOf(memoryBudgetBytes(context) / 3, 16 * 1024 * 1024))
    private val viewerCache = LRUCache<String, Bitmap>(budget = minOf(memoryBudgetBytes(context), 48 * 1024 * 1024))

    private val thumbGate = Semaphore(permits = 2)
    private val viewerGate = Semaphore(permits = 1)

    suspend fun loadThumbnail(source: PhotoSource, photo: PhotoWithCull, maxPx: Int = 360): Bitmap? =
        withContext(Dispatchers.IO) {
            val key = cacheKey(source.rootUri, photo)
            thumbCache.value(key)?.let { return@withContext it }

            val diskFile = File(thumbDir, "$key.jpg")
            if (diskFile.exists()) {
                val opts = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.RGB_565 }
                runCatching { BitmapFactory.decodeFile(diskFile.absolutePath, opts) }.getOrNull()?.let { bmp ->
                    thumbCache.insert(bmp, key, bmp.allocationByteCount)
                    return@withContext bmp
                }
            }

            thumbGate.withPermit {
                thumbCache.value(key)?.let { return@withPermit it }
                val bmp = safeDecode {
                    decodePhoto(source, photo, targetMaxPx = maxPx, minPreviewPx = 240, rgb565 = true)
                } ?: return@withPermit null
                thumbCache.insert(bmp, key, bmp.allocationByteCount)
                runCatching {
                    FileOutputStream(diskFile).use { out ->
                        bmp.compress(Bitmap.CompressFormat.JPEG, 82, out)
                    }
                }
                bmp
            }
        }

    suspend fun loadViewerBitmap(source: PhotoSource, photo: PhotoWithCull, targetMaxPx: Int = 2048): Bitmap? =
        withContext(Dispatchers.IO) {
            val key = "${cacheKey(source.rootUri, photo)}@$targetMaxPx"
            viewerCache.value(key)?.let { return@withContext it }
            viewerGate.withPermit {
                viewerCache.value(key)?.let { return@withPermit it }
                val bmp = safeDecode {
                    decodePhoto(source, photo, targetMaxPx = targetMaxPx, minPreviewPx = 1200, rgb565 = false)
                } ?: return@withPermit null
                viewerCache.insert(bmp, key, bmp.allocationByteCount)
                bmp
            }
        }

    suspend fun loadDetails(source: PhotoSource, photo: PhotoWithCull, previewBitmap: Bitmap?): PhotoDetails =
        withContext(Dispatchers.IO) {
            val exif = readExif(source, photo)
            val camera = ExifFormat.camera(
                exif?.getAttribute(ExifInterface.TAG_MAKE),
                exif?.getAttribute(ExifInterface.TAG_MODEL),
            )
            val lens = exif?.getAttribute(ExifInterface.TAG_LENS_MODEL)?.trim()?.ifEmpty { null }
            val shutter = exif?.getAttributeDouble(ExifInterface.TAG_EXPOSURE_TIME, 0.0)
                ?.takeIf { it > 0 }?.let { ExifFormat.shutter(it) }
            val aperture = exif?.getAttributeDouble(ExifInterface.TAG_F_NUMBER, 0.0)
                ?.takeIf { it > 0 }?.let { ExifFormat.aperture(it) }
            val iso = exif?.getAttributeInt(ExifInterface.TAG_PHOTOGRAPHIC_SENSITIVITY, 0)
                ?.takeIf { it > 0 }?.let { ExifFormat.iso(it) }
            val exposure = listOfNotNull(shutter, aperture, iso).joinToString(" · ").ifEmpty { null }

            val focal = exif?.getAttributeDouble(ExifInterface.TAG_FOCAL_LENGTH, 0.0)?.takeIf { it > 0 }
            val focal35 = exif?.getAttributeInt(ExifInterface.TAG_FOCAL_LENGTH_IN_35MM_FILM, 0)
                ?.takeIf { it > 0 }?.toDouble()
            val focalStr = ExifFormat.focalLength(focal, focal35)

            val date = photo.captureDate
                ?: exif?.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)
                ?: exif?.getAttribute(ExifInterface.TAG_DATETIME)

            val w = exif?.getAttributeInt(ExifInterface.TAG_IMAGE_WIDTH, 0)?.takeIf { it > 0 } ?: previewBitmap?.width
            val h = exif?.getAttributeInt(ExifInterface.TAG_IMAGE_LENGTH, 0)?.takeIf { it > 0 } ?: previewBitmap?.height
            val dims = if (w != null && h != null) "$w × $h" else null

            val hist = previewBitmap?.let { runCatching { computeHistogram(it) }.getOrNull() }
            PhotoDetails(
                camera = camera,
                lens = lens,
                exposure = exposure,
                focalLength = focalStr,
                date = date,
                dimensions = dims,
                fileSize = ExifFormat.fileSize(photo.size),
                histogram = hist,
            )
        }

    fun clearMemory() {
        thumbCache.removeAll()
        viewerCache.removeAll()
    }

    private inline fun safeDecode(block: () -> Bitmap?): Bitmap? =
        try {
            block()
        } catch (_: OutOfMemoryError) {
            clearMemory()
            null
        } catch (_: Throwable) {
            null
        }

    private fun decodePhoto(
        source: PhotoSource,
        photo: PhotoWithCull,
        targetMaxPx: Int,
        minPreviewPx: Int,
        rgb565: Boolean,
    ): Bitmap? {
        val type = PhotoFileType.of(photo.fileName)
        if (type == PhotoFileType.VIDEO) {
            return decodeVideoFrame(source, photo.docId, targetMaxPx)
        }
        if (type == PhotoFileType.RAW) {
            var smallFallback: Pair<ByteArray, Int>? = null
            source.openByteSource(photo.docId, photo.size)?.use { bs ->
                val preview = EmbeddedPreviews.find(bs)
                if (preview != null) {
                    val effectiveOrientation = effectivePreviewOrientation(preview)
                    if (maxOf(preview.width, preview.height) >= minPreviewPx) {
                        return decodeJpegBytes(preview.jpeg(bs), targetMaxPx, rgb565, effectiveOrientation)
                    } else if (maxOf(preview.width, preview.height) >= 160) {
                        smallFallback = preview.jpeg(bs) to effectiveOrientation
                    }
                }
            }
            if (smallFallback != null && rgb565) {
                return decodeJpegBytes(smallFallback!!.first, targetMaxPx, rgb565 = true, smallFallback!!.second)
            }
            // Fallback for phone DNGs without a large embedded JPEG: Android ImageDecoder
            val decoded = decodeViaImageDecoder(source, photo.docId, targetMaxPx)
            if (decoded != null) return decoded
            return smallFallback?.let { decodeJpegBytes(it.first, targetMaxPx, rgb565, it.second) }
        }
        return decodeViaImageDecoder(source, photo.docId, targetMaxPx)
    }

    private fun decodeVideoFrame(source: PhotoSource, docId: String, targetMaxPx: Int): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, source.uriForShare(docId))
            retriever.getScaledFrameAtTime(
                1_000_000L,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                targetMaxPx,
                targetMaxPx,
            ) ?: retriever.getScaledFrameAtTime(
                0L,
                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                targetMaxPx,
                targetMaxPx,
            )
        } catch (_: Throwable) {
            null
        } finally {
            runCatching { retriever.release() }
        }
    }

    /**
     * Many cameras (Sony ARW, Nikon NEF, Canon CR2/CR3, DNG) store Orientation=1 (Normal) inside the
     * embedded JPEG while placing the actual portrait rotation (6/8) in the RAW's IFD0/CMT1.
     * Prefer the JPEG's orientation only when it actually rotates (> 1); otherwise use rawOrientation.
     */
    private fun effectivePreviewOrientation(preview: app.rawboy.viewer.core.EmbeddedPreview): Int = when {
        preview.jpegOrientation > 1 -> preview.jpegOrientation
        preview.rawOrientation > 1 -> preview.rawOrientation
        else -> 0
    }

    private fun decodeJpegBytes(
        jpeg: ByteArray,
        targetMaxPx: Int,
        rgb565: Boolean,
        knownOrientation: Int = 0,
    ): Bitmap? {
        val orientation = if (knownOrientation > 1) {
            knownOrientation
        } else {
            runCatching {
                ExifInterface(ByteArrayInputStream(jpeg)).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL,
                )
            }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)
        }

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, bounds)
        val longest = maxOf(bounds.outWidth, bounds.outHeight)
        var sample = 1
        while (longest / (sample * 2) >= targetMaxPx) sample *= 2

        val opts = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = if (rgb565) Bitmap.Config.RGB_565 else Bitmap.Config.ARGB_8888
        }
        val raw = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, opts) ?: return null
        return applyOrientation(raw, orientation)
    }

    private fun decodeViaImageDecoder(source: PhotoSource, docId: String, targetMaxPx: Int): Bitmap? =
        runCatching {
            val src = ImageDecoder.createSource(context.contentResolver, source.uriForShare(docId))
            ImageDecoder.decodeBitmap(src) { decoder, info, _ ->
                val longest = maxOf(info.size.width, info.size.height)
                if (longest > targetMaxPx && longest > 0) {
                    val scale = targetMaxPx.toFloat() / longest.toFloat()
                    decoder.setTargetSize(
                        maxOf(1, (info.size.width * scale).toInt()),
                        maxOf(1, (info.size.height * scale).toInt()),
                    )
                }
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
        }.getOrNull()

    private fun readExif(source: PhotoSource, photo: PhotoWithCull): ExifInterface? =
        runCatching {
            source.openInputStream(photo.docId)?.use { ExifInterface(it) }
        }.getOrNull()

    private fun computeHistogram(bitmap: Bitmap): Histogram {
        val maxSide = 256
        val longest = maxOf(bitmap.width, bitmap.height)
        val scaled = if (longest > maxSide) {
            val s = maxSide.toFloat() / longest
            Bitmap.createScaledBitmap(bitmap, maxOf(1, (bitmap.width * s).toInt()), maxOf(1, (bitmap.height * s).toInt()), false)
        } else {
            bitmap
        }
        val pixels = IntArray(scaled.width * scaled.height)
        scaled.getPixels(pixels, 0, scaled.width, 0, 0, scaled.width, scaled.height)
        if (scaled !== bitmap) scaled.recycle()
        return Histogram.fromArgb(pixels)
    }

    private fun applyOrientation(bitmap: Bitmap, orientation: Int): Bitmap {
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> {
                matrix.setRotate(180f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.setRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.setRotate(-90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
            else -> return bitmap
        }
        val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        if (rotated !== bitmap) bitmap.recycle()
        return rotated
    }

    private fun cacheKey(rootUri: String, photo: PhotoWithCull): String {
        val raw = "v2|$rootUri|${photo.relPath}|${photo.size}|${photo.mtime}"
        val digest = MessageDigest.getInstance("SHA-256").digest(raw.toByteArray())
        return digest.take(12).joinToString("") { "%02x".format(it) }
    }

    companion object {
        private fun memoryBudgetBytes(context: Context): Int {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val classMb = am.memoryClass.coerceAtLeast(64)
            return (classMb * 1024 * 1024) / 4
        }
    }
}
