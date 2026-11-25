package app.rawboy.viewer.ui

import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.rawboy.viewer.core.CaptureDate
import app.rawboy.viewer.core.Flag
import app.rawboy.viewer.core.FlagFilter
import app.rawboy.viewer.core.PhotoFileType
import app.rawboy.viewer.core.PhotoGroups
import app.rawboy.viewer.core.PhotoOrder
import app.rawboy.viewer.core.PhotoSort
import app.rawboy.viewer.core.PrefetchPlan
import app.rawboy.viewer.core.Rating
import app.rawboy.viewer.data.CullEntity
import app.rawboy.viewer.data.PhotoEntity
import app.rawboy.viewer.data.PhotoWithCull
import app.rawboy.viewer.data.SourceEntity
import app.rawboy.viewer.data.ViewerDatabase
import app.rawboy.viewer.data.ViewerPrefs
import app.rawboy.viewer.data.ViewerSettings
import app.rawboy.viewer.handoff.AutoImportMode
import app.rawboy.viewer.handoff.RawBoyHandOff
import app.rawboy.viewer.imaging.ImageRepository
import app.rawboy.viewer.sources.LocalSafSource
import app.rawboy.viewer.sources.PhotoSource
import app.rawboy.viewer.xmp.ConflictResolution
import app.rawboy.viewer.xmp.XmpConflict
import app.rawboy.viewer.xmp.XmpSyncResult
import app.rawboy.viewer.xmp.XmpSyncService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class UndoEntry(val before: List<CullEntity>)

data class ViewerUiState(
    val sources: List<SourceEntity> = emptyList(),
    val activeSource: SourceEntity? = null,
    val allPhotos: List<PhotoWithCull> = emptyList(),
    val visiblePhotos: List<PhotoWithCull> = emptyList(),
    val filter: FlagFilter = FlagFilter.ALL,
    val minStars: Int = 0,
    val filterCounts: Map<FlagFilter, Int> = emptyMap(),
    val unsyncedXmpCount: Int = 0,
    val binnedCount: Int = 0,
    val selectedIds: Set<Long> = emptySet(),
    val viewerPhotoId: Long? = null,
    val isScanning: Boolean = false,
    val statusMessage: String? = null,
    val canUndo: Boolean = false,
    val prefs: ViewerPrefs = ViewerPrefs(),
    val rawBoyInstalled: Boolean = false,
    val rawBoyAutoInstalled: Boolean = false,
    val pendingConflicts: List<XmpConflict>? = null,
    val pendingConflictTargets: List<PhotoWithCull> = emptyList(),
    val xmpResult: XmpSyncResult? = null,
    val showAutoSendSheet: Boolean = false,
    val autoSendTargets: List<PhotoWithCull> = emptyList(),
    val showSettings: Boolean = false,
)

class ViewerViewModel(application: Application) : AndroidViewModel(application) {
    private val db = ViewerDatabase.get(application)
    private val sourceDao = db.sourceDao()
    private val photoDao = db.photoDao()
    private val cullDao = db.cullDao()
    private val settings = ViewerSettings(application)
    val images = ImageRepository(application)
    val handOff = RawBoyHandOff(application, db.batchDao())
    private val xmpSync = XmpSyncService(photoDao, cullDao)

    private val _state = MutableStateFlow(
        ViewerUiState(
            rawBoyInstalled = handOff.isRawBoyInstalled(),
            rawBoyAutoInstalled = handOff.isRawBoyAutoInstalled(),
        )
    )
    val state: StateFlow<ViewerUiState> = _state.asStateFlow()

    private val _activePhotoSource = MutableStateFlow<PhotoSource?>(null)
    val activePhotoSource: StateFlow<PhotoSource?> = _activePhotoSource.asStateFlow()

    private val undoStack = ArrayDeque<UndoEntry>()
    private var observeJob: Job? = null
    private var prefetchJob: Job? = null

    init {
        viewModelScope.launch {
            sourceDao.observeAll().collect { sources ->
                _state.update { it.copy(sources = sources) }
            }
        }
        viewModelScope.launch {
            settings.prefs.collect { prefs ->
                _state.update { s ->
                    val sorted = sortAndFilter(s.allPhotos, s.filter, s.minStars, prefs.sort)
                    s.copy(prefs = prefs, visiblePhotos = sorted)
                }
            }
        }
        viewModelScope.launch {
            val prefs = settings.prefs.first()
            val lastUri = prefs.lastFolderUri
            if (lastUri != null) {
                runCatching { openFolder(Uri.parse(lastUri), persistPermission = false) }
            }
        }
    }

    fun openFolder(treeUri: Uri, persistPermission: Boolean = true) {
        viewModelScope.launch {
            val app = getApplication<Application>()
            if (persistPermission) {
                val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                runCatching { app.contentResolver.takePersistableUriPermission(treeUri, flags) }
                    .onFailure {
                        runCatching {
                            app.contentResolver.takePersistableUriPermission(
                                treeUri,
                                Intent.FLAG_GRANT_READ_URI_PERMISSION,
                            )
                        }
                    }
            }

            val saf = LocalSafSource(app, treeUri)
            _activePhotoSource.value = saf
            settings.setLastFolder(treeUri.toString())

            val existing = sourceDao.findByUri(treeUri.toString())
            val sourceId = if (existing != null) {
                sourceDao.touch(existing.id, saf.label)
                existing.id
            } else {
                sourceDao.upsert(SourceEntity(kind = "local_saf", rootUri = treeUri.toString(), label = saf.label))
            }
            val sourceEntity = sourceDao.findById(sourceId) ?: return@launch
            _state.update {
                it.copy(
                    activeSource = sourceEntity,
                    selectedIds = emptySet(),
                    viewerPhotoId = null,
                    isScanning = true,
                    rawBoyInstalled = handOff.isRawBoyInstalled(),
                    rawBoyAutoInstalled = handOff.isRawBoyAutoInstalled(),
                )
            }

            observeSource(sourceId)
            scanSource(sourceEntity, saf)
        }
    }

    private fun observeSource(sourceId: Long) {
        observeJob?.cancel()
        observeJob = viewModelScope.launch {
            photoDao.observeActiveForSource(sourceId).collect { photos ->
                val ratings = photos.map { Rating(it.effectiveStars, Flag.fromDb(it.effectiveFlag)) }
                val counts = FlagFilter.counts(ratings)
                val unsynced = photos.count { it.needsXmpWrite }
                val binned = withContext(Dispatchers.IO) { photoDao.getBinnedForSource(sourceId).size }
                _state.update { s ->
                    val visible = sortAndFilter(photos, s.filter, s.minStars, s.prefs.sort)
                    s.copy(
                        allPhotos = photos,
                        visiblePhotos = visible,
                        filterCounts = counts,
                        unsyncedXmpCount = unsynced,
                        binnedCount = binned,
                    )
                }
            }
        }
    }

    private suspend fun scanSource(sourceEntity: SourceEntity, saf: PhotoSource) {
        withContext(Dispatchers.IO) {
            val entries = saf.listFiles().filter { !it.isDirectory }
            val byLower = entries.associateBy { it.name.lowercase() }
            val groups = PhotoGroups.group(entries.map { it.name })
                .filter { PhotoFileType.of(it.main) != PhotoFileType.VIDEO }

            val existingRows = photoDao.getAllForSource(sourceEntity.id)
            val existingByRel = existingRows.associateBy { it.relPath.lowercase() }
            val matchedIds = HashSet<Long>()

            for (g in groups) {
                val mainEntry = byLower[g.main.lowercase()] ?: continue
                val compIds = g.companions.mapNotNull { byLower[it.lowercase()]?.docId }
                val prev = existingByRel[g.main.lowercase()]
                    ?: existingRows.singleOrNull {
                        it.id !in matchedIds && it.size == mainEntry.size && it.mtime == mainEntry.mtime
                    }

                val entity = PhotoEntity(
                    id = prev?.id ?: 0L,
                    sourceId = sourceEntity.id,
                    relPath = g.main,
                    docId = mainEntry.docId,
                    companionNames = g.companions.joinToString("\n"),
                    companionDocIds = compIds.joinToString("\n"),
                    sidecarNames = g.sidecars.joinToString("\n"),
                    size = mainEntry.size,
                    mtime = mainEntry.mtime,
                    captureDate = prev?.captureDate ?: PhotoOrder.fileDate(mainEntry.mtime),
                    groupKey = g.stem.lowercase(),
                    inBin = false,
                    orphanedAt = null,
                )
                val id = photoDao.upsert(entity)
                matchedIds.add(id)
            }

            val missingIds = existingRows.filter { it.id !in matchedIds && !it.inBin && it.orphanedAt == null }.map { it.id }
            if (missingIds.isNotEmpty()) photoDao.markOrphaned(missingIds, System.currentTimeMillis())
            photoDao.purgeOldOrphans(System.currentTimeMillis() - 30L * 86_400_000L)

            // Seed ratings from existing XMP sidecars on first open of this folder
            if (!sourceEntity.seededFromXmp) {
                val currentPhotos = photoDao.observeActiveForSource(sourceEntity.id).first()
                xmpSync.seedFromExistingSidecars(saf, currentPhotos)
                sourceDao.markSeeded(sourceEntity.id)
            }

            _state.update { it.copy(isScanning = false) }

            // Backfill exact EXIF capture dates off the main thread
            val currentPhotos = photoDao.observeActiveForSource(sourceEntity.id).first()
            for (p in currentPhotos) {
                saf.openByteSource(p.docId, p.size)?.use { bs ->
                    CaptureDate.find(bs)?.let { date ->
                        if (date != p.captureDate) photoDao.updateCaptureDate(p.id, date)
                    }
                }
            }
        }
    }

    fun refreshFolder() {
        val src = _state.value.activeSource ?: return
        val saf = _activePhotoSource.value ?: return
        viewModelScope.launch {
            _state.update { it.copy(isScanning = true) }
            scanSource(src, saf)
        }
    }

    fun setFilter(filter: FlagFilter) {
        _state.update { s ->
            s.copy(filter = filter, visiblePhotos = sortAndFilter(s.allPhotos, filter, s.minStars, s.prefs.sort))
        }
    }

    fun setMinStars(minStars: Int) {
        val next = if (_state.value.minStars == minStars) 0 else minStars
        _state.update { s ->
            s.copy(minStars = next, visiblePhotos = sortAndFilter(s.allPhotos, s.filter, next, s.prefs.sort))
        }
    }

    fun toggleSort() {
        val next = if (_state.value.prefs.sort == PhotoSort.DATE) PhotoSort.NAME else PhotoSort.DATE
        viewModelScope.launch { settings.setSort(next) }
    }

    fun openViewer(photoId: Long) {
        _state.update { it.copy(viewerPhotoId = photoId) }
    }

    fun closeViewer() {
        _state.update { it.copy(viewerPhotoId = null) }
    }

    fun toggleSelect(photoId: Long) {
        _state.update { s ->
            val next = if (photoId in s.selectedIds) s.selectedIds - photoId else s.selectedIds + photoId
            s.copy(selectedIds = next)
        }
    }

    fun selectAllVisible() {
        _state.update { s -> s.copy(selectedIds = s.visiblePhotos.map { it.id }.toSet()) }
    }

    fun clearSelection() {
        _state.update { it.copy(selectedIds = emptySet()) }
    }

    fun ratePhotos(photoIds: List<Long>, stars: Int) {
        if (photoIds.isEmpty()) return
        viewModelScope.launch(Dispatchers.IO) {
            val before = photoIds.map { id -> cullDao.get(id) ?: CullEntity(photoId = id) }
            val currentRatings = before.map { Rating(it.stars, Flag.fromDb(it.flag)) }
            val updatedRatings = Rating.withStars(currentRatings, stars)
            val now = System.currentTimeMillis()
            val after = before.zip(updatedRatings) { prev, r ->
                prev.copy(stars = r.stars, flag = r.flag?.dbValue ?: 0, updatedAt = now)
            }
            pushUndo(before)
            cullDao.upsertAll(after)
        }
    }

    fun flagPhotos(photoIds: List<Long>, flag: Flag?) {
        if (photoIds.isEmpty()) return
        viewModelScope.launch(Dispatchers.IO) {
            val before = photoIds.map { id -> cullDao.get(id) ?: CullEntity(photoId = id) }
            val now = System.currentTimeMillis()
            val after = if (flag == null) {
                before.map { it.copy(flag = 0, updatedAt = now) }
            } else {
                val currentRatings = before.map { Rating(it.stars, Flag.fromDb(it.flag)) }
                val updatedRatings = Rating.withFlag(currentRatings, flag)
                before.zip(updatedRatings) { prev, r ->
                    prev.copy(stars = r.stars, flag = r.flag?.dbValue ?: 0, updatedAt = now)
                }
            }
            pushUndo(before)
            cullDao.upsertAll(after)
        }
    }

    fun undo() {
        val entry = undoStack.removeLastOrNull() ?: return
        _state.update { it.copy(canUndo = undoStack.isNotEmpty()) }
        viewModelScope.launch(Dispatchers.IO) {
            cullDao.upsertAll(entry.before)
        }
    }

    private fun pushUndo(before: List<CullEntity>) {
        if (undoStack.size >= 50) undoStack.removeFirst()
        undoStack.addLast(UndoEntry(before))
        _state.update { it.copy(canUndo = true) }
    }

    fun prefetchAround(index: Int, forward: Boolean = true) {
        val saf = _activePhotoSource.value ?: return
        val list = _state.value.visiblePhotos
        val order = PrefetchPlan.order(index, list.size, forward, ahead = 2, behind = 1)
        prefetchJob?.cancel()
        prefetchJob = viewModelScope.launch(Dispatchers.IO) {
            for (i in order) {
                val p = list.getOrNull(i) ?: continue
                images.loadViewerBitmap(saf, p)
            }
        }
    }

    // --- XMP on-demand write (default conflict resolution: KEEP_XMP / phone loses) ---

    fun requestWriteXmp(selectionOnly: Boolean = false) {
        val saf = _activePhotoSource.value ?: return
        val s = _state.value
        val targets = if (selectionOnly && s.selectedIds.isNotEmpty()) {
            s.allPhotos.filter { it.id in s.selectedIds && it.needsXmpWrite }
        } else {
            s.allPhotos.filter { it.needsXmpWrite }
        }
        if (targets.isEmpty()) {
            showStatus("All ratings are already in XMP")
            return
        }
        viewModelScope.launch {
            val conflicts = xmpSync.findConflicts(saf, targets)
            if (conflicts.isNotEmpty()) {
                _state.update { it.copy(pendingConflicts = conflicts, pendingConflictTargets = targets) }
            } else {
                val res = xmpSync.writeRatings(saf, targets, ConflictResolution.KEEP_XMP)
                _state.update { it.copy(xmpResult = res) }
            }
        }
    }

    fun resolveXmpConflicts(resolution: ConflictResolution) {
        val saf = _activePhotoSource.value ?: return
        val targets = _state.value.pendingConflictTargets
        _state.update { it.copy(pendingConflicts = null, pendingConflictTargets = emptyList()) }
        viewModelScope.launch {
            val res = xmpSync.writeRatings(saf, targets, resolution)
            _state.update { it.copy(xmpResult = res) }
        }
    }

    fun dismissXmpDialogs() {
        _state.update { it.copy(pendingConflicts = null, pendingConflictTargets = emptyList(), xmpResult = null) }
    }

    // --- Send to RawBoy / RawBoy Auto ---

    fun sendToRawBoy(targets: List<PhotoWithCull>) {
        val saf = _activePhotoSource.value ?: return
        if (targets.isEmpty()) return
        viewModelScope.launch {
            if (_state.value.prefs.writeXmpBeforeSend) {
                xmpSync.writeRatings(saf, targets, ConflictResolution.KEEP_XMP)
            }
            val ok = handOff.sendToRawBoy(saf, targets)
            if (!ok) {
                handOff.shareSystem(saf, targets, _state.value.prefs.includeJpegsInBatch)
            }
        }
    }

    fun openAutoSendSheet(targets: List<PhotoWithCull>) {
        if (targets.isEmpty()) return
        _state.update { it.copy(showAutoSendSheet = true, autoSendTargets = targets) }
    }

    fun dismissAutoSendSheet() {
        _state.update { it.copy(showAutoSendSheet = false, autoSendTargets = emptyList()) }
    }

    fun sendToRawBoyAuto(mode: AutoImportMode, includeJpegs: Boolean) {
        val saf = _activePhotoSource.value ?: return
        val targets = _state.value.autoSendTargets
        dismissAutoSendSheet()
        if (targets.isEmpty()) return
        viewModelScope.launch {
            settings.setLastAutoMode(mode.raw)
            settings.setIncludeJpegsInBatch(includeJpegs)
            if (_state.value.prefs.writeXmpBeforeSend) {
                xmpSync.writeRatings(saf, targets, ConflictResolution.KEEP_XMP)
            }
            val ok = handOff.sendToRawBoyAuto(saf, targets, mode, includeJpegs)
            if (!ok) {
                handOff.shareSystem(saf, targets, includeJpegs)
            }
        }
    }

    fun shareTargets(targets: List<PhotoWithCull>) {
        val saf = _activePhotoSource.value ?: return
        if (targets.isEmpty()) return
        viewModelScope.launch {
            handOff.shareSystem(saf, targets, _state.value.prefs.includeJpegsInBatch)
        }
    }

    // --- Optional _bin move / restore ---

    fun moveRejectsToBin() {
        val saf = _activePhotoSource.value ?: return
        val rejects = _state.value.allPhotos.filter { it.effectiveFlag == Flag.REJECT.dbValue }
        if (rejects.isEmpty()) {
            showStatus("No rejected photos to move")
            return
        }
        viewModelScope.launch(Dispatchers.IO) {
            val moved = saf.moveToBin(rejects.map { it.docId })
            for (p in rejects) {
                val newId = moved[p.docId] ?: continue
                photoDao.updateBinState(p.id, inBin = true, docId = newId)
            }
            showStatus("Moved ${moved.size} rejects to _bin")
        }
    }

    fun restoreFromBin() {
        val saf = _activePhotoSource.value ?: return
        val sourceId = _state.value.activeSource?.id ?: return
        viewModelScope.launch(Dispatchers.IO) {
            val binned = photoDao.getBinnedForSource(sourceId)
            if (binned.isEmpty()) return@launch
            val restored = saf.restoreFromBin(binned.map { it.docId })
            for (p in binned) {
                val newId = restored[p.docId] ?: continue
                photoDao.updateBinState(p.id, inBin = false, docId = newId)
            }
            showStatus("Restored ${restored.size} photos from _bin")
        }
    }

    // --- Settings ---

    fun openSettings() = _state.update { it.copy(showSettings = true) }
    fun dismissSettings() = _state.update { it.copy(showSettings = false) }
    fun setAutoAdvance(v: Boolean) = viewModelScope.launch { settings.setAutoAdvance(v) }
    fun setWriteXmpBeforeSend(v: Boolean) = viewModelScope.launch { settings.setWriteXmpBeforeSend(v) }
    fun setIncludeJpegsInBatch(v: Boolean) = viewModelScope.launch { settings.setIncludeJpegsInBatch(v) }
    fun setEnableBin(v: Boolean) = viewModelScope.launch { settings.setEnableBin(v) }

    fun clearStatus() = _state.update { it.copy(statusMessage = null) }
    private fun showStatus(msg: String) = _state.update { it.copy(statusMessage = msg) }

    private fun sortAndFilter(
        photos: List<PhotoWithCull>,
        filter: FlagFilter,
        minStars: Int,
        sort: PhotoSort,
    ): List<PhotoWithCull> {
        val cmp = PhotoOrder.comparator(sort)
        return photos
            .filter { filter.passes(Rating(it.effectiveStars, Flag.fromDb(it.effectiveFlag)), minStars) }
            .sortedWith { a, b -> cmp.compare(a.captureDate to a.relPath, b.captureDate to b.relPath) }
    }
}
