package app.rawboy.viewer.sources

import android.content.Context
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import app.rawboy.viewer.core.BlockCachedSource
import app.rawboy.viewer.core.ByteSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.FileInputStream
import java.io.InputStream
import java.nio.ByteBuffer

/**
 * Local folder backed by Android's Storage Access Framework (`ACTION_OPEN_DOCUMENT_TREE`).
 *
 * Uses a single `DocumentsContract` query per folder instead of `DocumentFile.listFiles()` to avoid
 * per-file IPC overhead, and reads raw files via `ParcelFileDescriptor` + `FileChannel` so only the
 * embedded preview bytes are touched.
 */
class LocalSafSource(
    private val context: Context,
    private val treeUri: Uri,
) : PhotoSource {

    private val resolver = context.contentResolver
    private val rootDocId: String = DocumentsContract.getTreeDocumentId(treeUri)
    private val dirDocIds = java.util.concurrent.ConcurrentHashMap<String, String>().apply {
        put("", rootDocId)
    }

    override val rootUri: String get() = treeUri.toString()

    override val label: String
        get() = DocumentFile.fromTreeUri(context, treeUri)?.name
            ?: rootDocId.substringAfterLast('/').substringAfterLast(':')

    override suspend fun listFiles(): List<SourceFileEntry> = withContext(Dispatchers.IO) {
        val out = ArrayList<SourceFileEntry>(256)
        val queue = ArrayDeque<Triple<String, String, Int>>() // (dirDocId, relDir, depth)
        queue.add(Triple(rootDocId, "", 0))
        while (queue.isNotEmpty()) {
            val (dirId, relDir, depth) = queue.removeFirst()
            dirDocIds[relDir] = dirId
            val children = queryChildren(dirId, relDir)
            for (entry in children) {
                if (entry.isDirectory) {
                    if (depth < MAX_DEPTH && entry.name != BIN_DIR_NAME && !entry.name.startsWith(".")) {
                        val childRel = if (relDir.isEmpty()) entry.name else "$relDir/${entry.name}"
                        dirDocIds[childRel] = entry.docId
                        queue.add(Triple(entry.docId, childRel, depth + 1))
                    }
                } else {
                    out.add(entry)
                }
            }
        }
        out
    }

    private fun queryChildren(parentDocId: String, parentDir: String): List<SourceFileEntry> {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        val out = ArrayList<SourceFileEntry>(256)
        resolver.query(childrenUri, projection, null, null, null)?.use { c ->
            val iId = c.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val iName = c.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val iSize = c.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
            val iMtime = c.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            val iMime = c.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
            while (c.moveToNext()) {
                val id = if (iId >= 0) c.getString(iId) else continue
                val name = if (iName >= 0) c.getString(iName) else continue
                val size = if (iSize >= 0 && !c.isNull(iSize)) c.getLong(iSize) else 0L
                val mtime = if (iMtime >= 0 && !c.isNull(iMtime)) c.getLong(iMtime) else 0L
                val mime = if (iMime >= 0 && !c.isNull(iMime)) c.getString(iMime) else ""
                val isDir = mime == DocumentsContract.Document.MIME_TYPE_DIR
                out.add(SourceFileEntry(id, name, size, mtime, mime, isDir, parentDir, parentDocId))
            }
        }
        return out
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

    override suspend fun readText(docId: String): String? = withContext(Dispatchers.IO) {
        runCatching {
            resolver.openInputStream(uriForShare(docId))?.use { it.readBytes().toString(Charsets.UTF_8) }
        }.getOrNull()
    }

    override suspend fun findChildByName(name: String, parentDir: String): SourceFileEntry? = withContext(Dispatchers.IO) {
        val parentId = dirDocIds[parentDir] ?: rootDocId
        queryChildren(parentId, parentDir).firstOrNull { !it.isDirectory && it.name.equals(name, ignoreCase = true) }
    }

    override suspend fun writeText(name: String, existingDocId: String?, content: String, parentDir: String): String? =
        withContext(Dispatchers.IO) {
            val parentId = dirDocIds[parentDir] ?: rootDocId
            val targetDocId = existingDocId
                ?: findChildByName(name, parentDir)?.docId
                ?: createDocument(parentId, "application/rdf+xml", name)
                ?: return@withContext null
            val targetUri = uriForShare(targetDocId)
            val bytes = content.toByteArray(Charsets.UTF_8)
            val ok = runCatching {
                resolver.openOutputStream(targetUri, "wt")?.use { it.write(bytes) } != null
            }.getOrDefault(false)
            if (ok) targetDocId else null
        }

    override suspend fun moveToBin(docIds: List<String>): Map<String, String> = withContext(Dispatchers.IO) {
        val binId = getOrCreateBinDir() ?: return@withContext emptyMap()
        val moved = LinkedHashMap<String, String>()
        for (docId in docIds) {
            val newId = moveDocument(docId, rootDocId, binId)
            if (newId != null) moved[docId] = newId
        }
        moved
    }

    override suspend fun restoreFromBin(docIds: List<String>): Map<String, String> = withContext(Dispatchers.IO) {
        val binId = queryChildren(rootDocId, "")
            .firstOrNull { it.isDirectory && it.name == BIN_DIR_NAME }?.docId
            ?: return@withContext emptyMap()
        val restored = LinkedHashMap<String, String>()
        for (docId in docIds) {
            val newId = moveDocument(docId, binId, rootDocId)
            if (newId != null) restored[docId] = newId
        }
        restored
    }

    override fun uriForShare(docId: String): Uri =
        DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)

    private fun getOrCreateBinDir(): String? {
        val existing = queryChildren(rootDocId, "").firstOrNull { it.isDirectory && it.name == BIN_DIR_NAME }
        if (existing != null) return existing.docId
        return createDocument(rootDocId, DocumentsContract.Document.MIME_TYPE_DIR, BIN_DIR_NAME)
    }

    private fun createDocument(parentDocId: String, mimeType: String, name: String): String? {
        val parentUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, parentDocId)
        val created = runCatching {
            DocumentsContract.createDocument(resolver, parentUri, mimeType, name)
        }.getOrNull() ?: return null
        return DocumentsContract.getDocumentId(created)
    }

    private fun moveDocument(docId: String, fromParentDocId: String, toParentDocId: String): String? {
        val src = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
        val from = DocumentsContract.buildDocumentUriUsingTree(treeUri, fromParentDocId)
        val to = DocumentsContract.buildDocumentUriUsingTree(treeUri, toParentDocId)
        val moved = runCatching {
            DocumentsContract.moveDocument(resolver, src, from, to)
        }.getOrNull() ?: return null
        return DocumentsContract.getDocumentId(moved)
    }

    companion object {
        const val BIN_DIR_NAME = "_bin"
        private const val MAX_DEPTH = 6
    }
}
