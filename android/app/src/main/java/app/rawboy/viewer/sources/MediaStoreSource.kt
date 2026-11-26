package app.rawboy.viewer.sources

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import app.rawboy.viewer.core.BlockCachedSource
import app.rawboy.viewer.core.ByteSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.FileInputStream
import java.io.InputStream
import java.nio.ByteBuffer

/**
 * Built-in default [PhotoSource] backed by Android MediaStore (Pictures & DCIM),
 * grouped by relative subfolder path so the app opens straight into the user's photos.
 */
class MediaStoreSource(
    private val context: Context,
) : PhotoSource {
    private val resolver = context.contentResolver

    override val rootUri: String = ROOT_URI
    override val label: String = "Pictures & DCIM"

    override suspend fun listFiles(): List<SourceFileEntry> = withContext(Dispatchers.IO) {
        val out = ArrayList<SourceFileEntry>(256)
        queryMedia(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, "img:", out)
        queryMedia(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, "vid:", out)
        out
    }

    private fun queryMedia(collection: Uri, prefix: String, out: MutableList<SourceFileEntry>) {
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.RELATIVE_PATH,
        )
        val selection = "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ? OR ${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?"
        val args = arrayOf("Pictures/%", "DCIM/%")
        resolver.query(collection, projection, selection, args, null)?.use { c ->
            val iId = c.getColumnIndex(MediaStore.MediaColumns._ID)
            val iName = c.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
            val iSize = c.getColumnIndex(MediaStore.MediaColumns.SIZE)
            val iMtime = c.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)
            val iMime = c.getColumnIndex(MediaStore.MediaColumns.MIME_TYPE)
            val iRel = c.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
            while (c.moveToNext()) {
                val id = if (iId >= 0) c.getLong(iId) else continue
                val name = if (iName >= 0 && !c.isNull(iName)) c.getString(iName) else continue
                val size = if (iSize >= 0 && !c.isNull(iSize)) c.getLong(iSize) else 0L
                val mtimeSec = if (iMtime >= 0 && !c.isNull(iMtime)) c.getLong(iMtime) else 0L
                val mime = if (iMime >= 0 && !c.isNull(iMime)) c.getString(iMime) else ""
                val relDir = (if (iRel >= 0 && !c.isNull(iRel)) c.getString(iRel) else "").trim('/')
                out.add(
                    SourceFileEntry(
                        docId = "$prefix$id",
                        name = name,
                        size = size,
                        mtime = mtimeSec * 1000L,
                        mimeType = mime,
                        isDirectory = false,
                        parentDir = relDir,
                        parentDocId = relDir,
                    )
                )
            }
        }
    }

    override fun openByteSource(docId: String, size: Long): CloseableByteSource? {
        val uri = uriForShare(docId)
        val pfd = runCatching { resolver.openFileDescriptor(uri, "r") }.getOrNull() ?: return null
        val fis = FileInputStream(pfd.fileDescriptor)
        val channel = fis.channel
        val actualSize = runCatching { channel.size() }.getOrDefault(size).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
        val cached = BlockCachedSource(actualSize) { offset, length ->
            val buf = ByteBuffer.allocate(length)
            var total = 0
            var pos = offset
            while (total < length) {
                val n = runCatching { channel.read(buf, pos) }.getOrDefault(-1)
                if (n <= 0) break
                total += n
                pos += n
            }
            if (total == length) buf.array() else buf.array().copyOf(total)
        }
        return object : CloseableByteSource, ByteSource by cached {
            override fun close() {
                runCatching { fis.close() }
                runCatching { pfd.close() }
            }
        }
    }

    override fun openInputStream(docId: String): InputStream? =
        runCatching { resolver.openInputStream(uriForShare(docId)) }.getOrNull()

    override suspend fun readText(docId: String): String? = null
    override suspend fun findChildByName(name: String, parentDir: String): SourceFileEntry? = null
    override suspend fun writeText(name: String, existingDocId: String?, content: String, parentDir: String): String? = null

    override suspend fun deleteDocuments(docIds: List<String>): Set<String> = withContext(Dispatchers.IO) {
        val deleted = HashSet<String>(docIds.size)
        for (docId in docIds) {
            val rows = runCatching { resolver.delete(uriForShare(docId), null, null) }.getOrDefault(0)
            if (rows > 0) deleted.add(docId)
        }
        deleted
    }

    override suspend fun moveToBin(docIds: List<String>): Map<String, String> = emptyMap()
    override suspend fun restoreFromBin(docIds: List<String>): Map<String, String> = emptyMap()

    override fun uriForShare(docId: String): Uri {
        val isVideo = docId.startsWith("vid:")
        val id = docId.substringAfter(':').toLongOrNull() ?: 0L
        val base = if (isVideo) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        return ContentUris.withAppendedId(base, id)
    }

    companion object {
        const val ROOT_URI = "mediastore://pictures-dcim"
    }
}
