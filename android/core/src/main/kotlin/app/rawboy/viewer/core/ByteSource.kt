package app.rawboy.viewer.core

/**
 * Random access to a file's bytes, so parsers read only what they need (a preview's few kilobytes of markers, not a
 * 60 MB raw). Reads past the end return fewer bytes.
 * A port of RawBoyBrowseKit's `ByteSource.swift`: keep the two in step.
 */
interface ByteSource {
    val size: Int
    fun read(offset: Int, length: Int): ByteArray
}

/** Bytes in memory (tests, small files). */
class BytesSource(val bytes: ByteArray) : ByteSource {
    override val size: Int get() = bytes.size

    override fun read(offset: Int, length: Int): ByteArray {
        if (offset < 0 || length <= 0 || offset >= bytes.size) return ByteArray(0)
        val end = minOf(offset + length, bytes.size)
        return bytes.copyOfRange(offset, end)
    }
}

/**
 * A random-access byte source backed by 64 KB cached blocks (parsers make many small reads close together).
 * Large reads (> 256 KB, e.g. a whole preview) bypass the block cache.
 */
class BlockCachedSource(
    override val size: Int,
    private val readAt: (offset: Long, length: Int) -> ByteArray,
) : ByteSource {
    private val blocks = HashMap<Int, ByteArray>()

    override fun read(offset: Int, length: Int): ByteArray {
        if (offset < 0 || length <= 0 || offset >= size) return ByteArray(0)
        val end = minOf(offset + length, size)
        val total = end - offset
        if (total > BLOCK_SIZE * 4) return readAt(offset.toLong(), total)
        val out = ByteArray(total)
        var written = 0
        var at = offset
        while (at < end) {
            val index = at / BLOCK_SIZE
            val block = block(index)
            val start = at - index * BLOCK_SIZE
            if (start >= block.size) break
            val take = minOf(block.size - start, end - at)
            System.arraycopy(block, start, out, written, take)
            written += take
            at += take
        }
        return if (written == total) out else out.copyOf(written)
    }

    private fun block(index: Int): ByteArray {
        blocks[index]?.let { return it }
        if (blocks.size >= MAX_BLOCKS) blocks.clear()
        val data = readAt(index.toLong() * BLOCK_SIZE, BLOCK_SIZE)
        blocks[index] = data
        return data
    }

    companion object {
        private const val BLOCK_SIZE = 1 shl 16
        private const val MAX_BLOCKS = 64
    }
}

// Reading numbers from byte arrays: out of range reads as 0, so truncated files parse as "nothing found".
internal fun ByteArray.u8(at: Int): Int =
    if (at in indices) this[at].toInt() and 0xFF else 0

internal fun ByteArray.u16(at: Int, le: Boolean): Int =
    if (le) u8(at) or (u8(at + 1) shl 8) else (u8(at) shl 8) or u8(at + 1)

internal fun ByteArray.u32(at: Int, le: Boolean): Int =
    if (le) u16(at, true) or (u16(at + 2, true) shl 16)
    else (u16(at, false) shl 16) or u16(at + 2, false)

internal fun ByteArray.u64be(at: Int): Long {
    val hi = u32(at, false).toLong() and 0xFFFFFFFFL
    val lo = u32(at + 4, false).toLong() and 0xFFFFFFFFL
    return (hi shl 32) or lo
}

internal fun ByteArray.ascii(from: Int, to: Int): String {
    if (from < 0 || to > size || from >= to) return ""
    return String(this, from, to - from, Charsets.UTF_8)
}

internal fun ByteSource.u8(at: Int): Int = read(at, 1).u8(0)
internal fun ByteSource.u16(at: Int, le: Boolean): Int = read(at, 2).u16(0, le)
internal fun ByteSource.u32(at: Int, le: Boolean): Int = read(at, 4).u32(0, le)
