package app.rawboy.viewer.xmp

import app.rawboy.viewer.core.Flag
import app.rawboy.viewer.core.PhotoGroup
import app.rawboy.viewer.core.PhotoGroups
import app.rawboy.viewer.core.Rating
import app.rawboy.viewer.core.XmpSidecar
import app.rawboy.viewer.data.CullDao
import app.rawboy.viewer.data.CullEntity
import app.rawboy.viewer.data.PhotoDao
import app.rawboy.viewer.data.PhotoWithCull
import app.rawboy.viewer.sources.PhotoSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** A photo whose XMP sidecar was rated elsewhere since this app last wrote it. */
data class XmpConflict(
    val photo: PhotoWithCull,
    val phoneRating: Rating,
    val xmpRating: Rating,
)

enum class ConflictResolution {
    /** Default per user decision: phone loses XMP fight; keep XMP rating and update local DB. */
    KEEP_XMP,
    /** Overwrite XMP sidecars with phone rating. */
    KEEP_PHONE,
    /** Leave both untouched. */
    SKIP,
}

data class XmpSyncResult(
    val written: Int,
    val keptXmp: Int,
    val skipped: Int,
    val failed: List<String>,
)

/**
 * On-demand XMP sidecar sync:
 * - Seeds local DB from existing sidecars when a folder is opened for the first time (read-only).
 * - Detects conflicts when writing ratings to XMP (default resolution: phone loses / XMP wins).
 * - Writes `xmp:Rating` and `rawboy:Pick` in place via `XmpSidecar`, preserving everything else byte for byte.
 */
class XmpSyncService(
    private val photoDao: PhotoDao,
    private val cullDao: CullDao,
) {
    /** Reads existing XMP sidecars on first open of a folder to seed the local DB without writing anything. */
    suspend fun seedFromExistingSidecars(
        source: PhotoSource,
        photos: List<PhotoWithCull>,
    ): Int = withContext(Dispatchers.IO) {
        val filesByLower = source.listFiles()
            .filter { !it.isDirectory && PhotoGroups.isSidecar(it.name) }
            .associateBy { it.name.lowercase() }
        var seeded = 0
        val now = System.currentTimeMillis()
        for (p in photos) {
            if (p.updatedAt != null) continue // already has local DB state
            val sidecarNames = p.sidecarNames.split('\n').filter { it.isNotEmpty() }
            if (sidecarNames.isEmpty()) continue
            var found: Rating? = null
            for (name in sidecarNames) {
                val entry = filesByLower[name.lowercase()] ?: continue
                val text = source.readText(entry.docId) ?: continue
                if (XmpSidecar.hasRating(text)) {
                    found = XmpSidecar.readRating(text)
                    break
                }
            }
            if (found != null) {
                val flagVal = found.flag?.dbValue ?: 0
                cullDao.upsert(
                    CullEntity(
                        photoId = p.id,
                        stars = found.stars,
                        flag = flagVal,
                        updatedAt = now,
                        xmpWrittenAt = now,
                        xmpStars = found.stars,
                        xmpFlag = flagVal,
                    )
                )
                seeded++
            }
        }
        seeded
    }

    /** Checks which photos in [targets] have an XMP conflict (rated elsewhere since last write). */
    suspend fun findConflicts(source: PhotoSource, targets: List<PhotoWithCull>): List<XmpConflict> =
        withContext(Dispatchers.IO) {
            val filesByLower = source.listFiles()
                .filter { !it.isDirectory && PhotoGroups.isSidecar(it.name) }
                .associateBy { it.name.lowercase() }
            val conflicts = ArrayList<XmpConflict>()
            for (p in targets) {
                if (!p.needsXmpWrite) continue
                val phoneRating = Rating(p.effectiveStars, Flag.fromDb(p.effectiveFlag))
                val lastWritten = Rating(p.xmpStars ?: 0, Flag.fromDb(p.xmpFlag ?: 0))
                val sidecarNames = p.sidecarNames.split('\n').filter { it.isNotEmpty() }
                var diskRating: Rating? = null
                for (name in sidecarNames) {
                    val entry = filesByLower[name.lowercase()] ?: continue
                    val text = source.readText(entry.docId) ?: continue
                    if (XmpSidecar.hasRating(text)) {
                        diskRating = XmpSidecar.readRating(text)
                        break
                    }
                }
                if (diskRating != null && diskRating != phoneRating && diskRating != lastWritten) {
                    conflicts.add(XmpConflict(p, phoneRating, diskRating))
                }
            }
            conflicts
        }

    /** Writes ratings for [targets] to XMP sidecars, applying [conflictResolution] to any conflicts. */
    suspend fun writeRatings(
        source: PhotoSource,
        targets: List<PhotoWithCull>,
        conflictResolution: ConflictResolution = ConflictResolution.KEEP_XMP,
    ): XmpSyncResult = withContext(Dispatchers.IO) {
        val filesByLower = source.listFiles()
            .filter { !it.isDirectory && PhotoGroups.isSidecar(it.name) }
            .associateBy { it.name.lowercase() }

        var written = 0
        var keptXmp = 0
        var skipped = 0
        val failed = ArrayList<String>()
        val now = System.currentTimeMillis()

        for (p in targets) {
            if (!p.needsXmpWrite) continue
            val phoneRating = Rating(p.effectiveStars, Flag.fromDb(p.effectiveFlag))
            val lastWritten = Rating(p.xmpStars ?: 0, Flag.fromDb(p.xmpFlag ?: 0))
            val existingNames = p.sidecarNames.split('\n').filter { it.isNotEmpty() }
            val group = PhotoGroup(
                stem = PhotoGroups.stem(p.relPath),
                main = p.relPath,
                companions = p.companionNames.split('\n').filter { it.isNotEmpty() },
                sidecars = existingNames,
            )

            // Check conflict against disk first
            var diskRating: Rating? = null
            for (name in existingNames) {
                val entry = filesByLower[name.lowercase()] ?: continue
                val text = source.readText(entry.docId) ?: continue
                if (XmpSidecar.hasRating(text)) {
                    diskRating = XmpSidecar.readRating(text)
                    break
                }
            }
            if (diskRating != null && diskRating != phoneRating && diskRating != lastWritten) {
                when (conflictResolution) {
                    ConflictResolution.KEEP_XMP -> {
                        val fv = diskRating.flag?.dbValue ?: 0
                        cullDao.upsert(
                            CullEntity(
                                photoId = p.id,
                                stars = diskRating.stars,
                                flag = fv,
                                updatedAt = now,
                                xmpWrittenAt = now,
                                xmpStars = diskRating.stars,
                                xmpFlag = fv,
                            )
                        )
                        keptXmp++
                        continue
                    }
                    ConflictResolution.SKIP -> {
                        skipped++
                        continue
                    }
                    ConflictResolution.KEEP_PHONE -> Unit
                }
            }

            val namesToWrite = PhotoGroups.sidecarNamesToWrite(group)
            var allOk = true
            val updatedNames = existingNames.toMutableSet()
            for (name in namesToWrite) {
                val entry = filesByLower[name.lowercase()]
                val oldText = entry?.let { source.readText(it.docId) }
                val newText = runCatching { XmpSidecar.writeRating(oldText, phoneRating) }.getOrNull()
                if (newText == null) {
                    allOk = false
                    continue
                }
                val docId = source.writeText(name, entry?.docId, newText)
                if (docId == null) {
                    allOk = false
                } else {
                    updatedNames.add(name)
                }
            }

            if (allOk) {
                cullDao.upsert(
                    CullEntity(
                        photoId = p.id,
                        stars = phoneRating.stars,
                        flag = p.effectiveFlag,
                        updatedAt = now,
                        xmpWrittenAt = now,
                        xmpStars = phoneRating.stars,
                        xmpFlag = p.effectiveFlag,
                    )
                )
                if (updatedNames.size != existingNames.size) {
                    photoDao.updateSidecarNames(p.id, updatedNames.sorted().joinToString("\n"))
                }
                written++
            } else {
                failed.add(p.relPath)
            }
        }
        XmpSyncResult(written = written, keptXmp = keptXmp, skipped = skipped, failed = failed)
    }
}
