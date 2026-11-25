package app.rawboy.viewer.data

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

@Entity(
    tableName = "sources",
    indices = [Index(value = ["rootUri"], unique = true)],
)
data class SourceEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val kind: String, // "local_saf" | "gdrive" (future)
    val rootUri: String,
    val label: String,
    val canWrite: Boolean = true,
    val seededFromXmp: Boolean = false,
    val lastOpenedAt: Long = System.currentTimeMillis(),
)

@Entity(
    tableName = "photos",
    foreignKeys = [
        ForeignKey(
            entity = SourceEntity::class,
            parentColumns = ["id"],
            childColumns = ["sourceId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [
        Index(value = ["sourceId", "relPath"], unique = true),
        Index(value = ["sourceId", "groupKey"]),
    ],
)
data class PhotoEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val sourceId: Long,
    val relPath: String, // main file name (or relative path)
    val docId: String,
    val companionNames: String = "", // '\n'-separated companion names (e.g. paired JPEG)
    val companionDocIds: String = "", // '\n'-separated companion docIds
    val sidecarNames: String = "", // '\n'-separated existing sidecar names
    val size: Long,
    val mtime: Long,
    val captureDate: String? = null, // EXIF "YYYY:MM:DD HH:MM:SS"
    val groupKey: String,
    val inBin: Boolean = false,
    val orphanedAt: Long? = null,
)

@Entity(
    tableName = "culls",
    foreignKeys = [
        ForeignKey(
            entity = PhotoEntity::class,
            parentColumns = ["id"],
            childColumns = ["photoId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
)
data class CullEntity(
    @PrimaryKey val photoId: Long,
    val stars: Int = 0, // 0..5
    val flag: Int = 0, // -1 reject, 0 none, 1 pick
    val updatedAt: Long = System.currentTimeMillis(),
    val xmpWrittenAt: Long = 0L,
    val xmpStars: Int = 0,
    val xmpFlag: Int = 0,
) {
    val needsXmpWrite: Boolean
        get() = updatedAt > xmpWrittenAt && (stars != xmpStars || flag != xmpFlag)
}

@Entity(tableName = "batches")
data class BatchEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val target: String, // "rawboy" | "rawboy_auto" | "share"
    val mode: String, // "looks" | "film" | "asis" | "edit" | "share"
    val sentAt: Long = System.currentTimeMillis(),
)

@Entity(
    tableName = "batch_items",
    primaryKeys = ["batchId", "photoId"],
    foreignKeys = [
        ForeignKey(
            entity = BatchEntity::class,
            parentColumns = ["id"],
            childColumns = ["batchId"],
            onDelete = ForeignKey.CASCADE,
        ),
        ForeignKey(
            entity = PhotoEntity::class,
            parentColumns = ["id"],
            childColumns = ["photoId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("photoId")],
)
data class BatchItemEntity(
    val batchId: Long,
    val photoId: Long,
)

data class PhotoWithCull(
    val id: Long,
    val sourceId: Long,
    val relPath: String,
    val docId: String,
    val companionNames: String,
    val companionDocIds: String,
    val sidecarNames: String,
    val size: Long,
    val mtime: Long,
    val captureDate: String?,
    val groupKey: String,
    val inBin: Boolean,
    val stars: Int?,
    val flag: Int?,
    val updatedAt: Long?,
    val xmpWrittenAt: Long?,
    val xmpStars: Int?,
    val xmpFlag: Int?,
    val sentToAutoCount: Int,
) {
    val effectiveStars: Int get() = stars ?: 0
    val effectiveFlag: Int get() = flag ?: 0
    val folderPath: String get() = relPath.substringBeforeLast('/', "")
    val fileName: String get() = relPath.substringAfterLast('/')
    val needsXmpWrite: Boolean
        get() {
            val u = updatedAt ?: 0L
            val w = xmpWrittenAt ?: 0L
            return u > w && (effectiveStars != (xmpStars ?: 0) || effectiveFlag != (xmpFlag ?: 0))
        }
}

@Dao
interface SourceDao {
    @Query("SELECT * FROM sources ORDER BY lastOpenedAt DESC")
    fun observeAll(): Flow<List<SourceEntity>>

    @Query("SELECT * FROM sources WHERE rootUri = :rootUri LIMIT 1")
    suspend fun findByUri(rootUri: String): SourceEntity?

    @Query("SELECT * FROM sources WHERE id = :id LIMIT 1")
    suspend fun findById(id: Long): SourceEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(source: SourceEntity): Long

    @Query("UPDATE sources SET lastOpenedAt = :ts, label = :label WHERE id = :id")
    suspend fun touch(id: Long, label: String, ts: Long = System.currentTimeMillis())

    @Query("UPDATE sources SET seededFromXmp = 1 WHERE id = :id")
    suspend fun markSeeded(id: Long)

    @Query("DELETE FROM sources WHERE id = :id")
    suspend fun delete(id: Long)
}

@Dao
interface PhotoDao {
    @Query(
        """
        SELECT p.id, p.sourceId, p.relPath, p.docId, p.companionNames, p.companionDocIds, p.sidecarNames,
               p.size, p.mtime, p.captureDate, p.groupKey, p.inBin,
               c.stars, c.flag, c.updatedAt, c.xmpWrittenAt, c.xmpStars, c.xmpFlag,
               (SELECT COUNT(*) FROM batch_items bi JOIN batches b ON b.id = bi.batchId
                WHERE bi.photoId = p.id AND b.target = 'rawboy_auto') AS sentToAutoCount
        FROM photos p
        LEFT JOIN culls c ON c.photoId = p.id
        WHERE p.sourceId = :sourceId AND p.orphanedAt IS NULL AND p.inBin = 0
        """
    )
    fun observeActiveForSource(sourceId: Long): Flow<List<PhotoWithCull>>

    @Query(
        """
        SELECT p.id, p.sourceId, p.relPath, p.docId, p.companionNames, p.companionDocIds, p.sidecarNames,
               p.size, p.mtime, p.captureDate, p.groupKey, p.inBin,
               c.stars, c.flag, c.updatedAt, c.xmpWrittenAt, c.xmpStars, c.xmpFlag,
               0 AS sentToAutoCount
        FROM photos p
        LEFT JOIN culls c ON c.photoId = p.id
        WHERE p.sourceId = :sourceId AND p.orphanedAt IS NULL AND p.inBin = 1
        """
    )
    suspend fun getBinnedForSource(sourceId: Long): List<PhotoWithCull>

    @Query("SELECT COUNT(*) FROM photos WHERE sourceId = :sourceId AND orphanedAt IS NULL AND inBin = 1")
    suspend fun countBinnedForSource(sourceId: Long): Int

    @Query("SELECT * FROM photos WHERE sourceId = :sourceId")
    suspend fun getAllForSource(sourceId: Long): List<PhotoEntity>

    @Upsert
    suspend fun upsert(photo: PhotoEntity): Long

    @Upsert
    suspend fun upsertAll(photos: List<PhotoEntity>): List<Long>

    @Query("UPDATE photos SET captureDate = :date WHERE id = :id")
    suspend fun updateCaptureDate(id: Long, date: String)

    @Query("UPDATE photos SET sidecarNames = :sidecarNames WHERE id = :id")
    suspend fun updateSidecarNames(id: Long, sidecarNames: String)

    @Query("UPDATE photos SET inBin = :inBin, docId = :docId WHERE id = :id")
    suspend fun updateBinState(id: Long, inBin: Boolean, docId: String)

    @Query("UPDATE photos SET orphanedAt = :ts WHERE id IN (:ids)")
    suspend fun markOrphaned(ids: List<Long>, ts: Long)

    @Query("DELETE FROM photos WHERE orphanedAt IS NOT NULL AND orphanedAt < :cutoff")
    suspend fun purgeOldOrphans(cutoff: Long)
}

@Dao
interface CullDao {
    @Query("SELECT * FROM culls WHERE photoId = :photoId LIMIT 1")
    suspend fun get(photoId: Long): CullEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(cull: CullEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(culls: List<CullEntity>)
}

@Dao
interface BatchDao {
    @Insert
    suspend fun insertBatch(batch: BatchEntity): Long

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertItems(items: List<BatchItemEntity>)
}

@Database(
    entities = [
        SourceEntity::class,
        PhotoEntity::class,
        CullEntity::class,
        BatchEntity::class,
        BatchItemEntity::class,
    ],
    version = 1,
    exportSchema = false,
)
abstract class ViewerDatabase : RoomDatabase() {
    abstract fun sourceDao(): SourceDao
    abstract fun photoDao(): PhotoDao
    abstract fun cullDao(): CullDao
    abstract fun batchDao(): BatchDao

    companion object {
        @Volatile private var instance: ViewerDatabase? = null

        fun get(context: Context): ViewerDatabase =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    ViewerDatabase::class.java,
                    "rawboy_viewer.db",
                ).build().also { instance = it }
            }
    }
}
