package app.rawboy.viewer.sources

import android.net.Uri
import app.rawboy.viewer.core.ByteSource
import java.io.Closeable
import java.io.InputStream

/** One file entry returned by a [PhotoSource] listing (metadata only, no file bytes read). */
data class SourceFileEntry(
    val docId: String,
    val name: String,
    val size: Long,
    val mtime: Long,
    val mimeType: String,
    val isDirectory: Boolean,
    val parentDir: String = "",
    val parentDocId: String = "",
)

/** A [ByteSource] paired with a handle that must be closed after use. */
interface CloseableByteSource : ByteSource, Closeable

/**
 * Abstraction over where a photo folder lives.
 * Implemented now by [LocalSafSource] (SAF tree on internal storage / SD / USB);
 * designed so a future `DriveSource` (Google Drive REST v3 + HTTP Range reads) plugs in cleanly.
 */
interface PhotoSource {
    val rootUri: String
    val label: String

    suspend fun listFiles(): List<SourceFileEntry>
    fun openByteSource(docId: String, size: Long): CloseableByteSource?
    fun openInputStream(docId: String): InputStream?
    suspend fun readText(docId: String): String?
    suspend fun findChildByName(name: String, parentDir: String = ""): SourceFileEntry?
    suspend fun writeText(name: String, existingDocId: String?, content: String, parentDir: String = ""): String?
    suspend fun deleteDocuments(docIds: List<String>): Set<String>
    suspend fun moveToBin(docIds: List<String>): Map<String, String>
    suspend fun restoreFromBin(docIds: List<String>): Map<String, String>
    fun uriForShare(docId: String): Uri
}
