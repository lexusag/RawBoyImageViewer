package app.rawboy.viewer.ui

import android.graphics.Bitmap
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.RestoreFromTrash
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Sort
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Undo
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.rawboy.viewer.core.Flag
import app.rawboy.viewer.core.FlagFilter
import app.rawboy.viewer.core.NaturalOrder
import app.rawboy.viewer.core.PhotoFileType
import app.rawboy.viewer.core.PhotoSort
import app.rawboy.viewer.data.PhotoWithCull
import app.rawboy.viewer.data.SourceEntity
import app.rawboy.viewer.imaging.ImageRepository
import app.rawboy.viewer.sources.PhotoSource

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BrowserScreen(
    state: ViewerUiState,
    photoSource: PhotoSource?,
    images: ImageRepository,
    isExpanded: Boolean,
    onPickFolder: () -> Unit,
    onOpenPictures: () -> Unit,
    onSelectSource: (SourceEntity) -> Unit,
    onOpenPhoto: (Long) -> Unit,
    onToggleSelect: (Long) -> Unit,
    onSelectAll: () -> Unit,
    onClearSelection: () -> Unit,
    onToggleFolderCollapsed: (String) -> Unit,
    onSetAllFoldersCollapsed: (Boolean) -> Unit,
    onToggleSelectFolder: (String) -> Unit,
    onSetFilter: (FlagFilter) -> Unit,
    onSetMinStars: (Int) -> Unit,
    onToggleSort: () -> Unit,
    onRefresh: () -> Unit,
    onRateSelected: (Int) -> Unit,
    onFlagSelected: (Flag?) -> Unit,
    onUndo: () -> Unit,
    onWriteXmp: (Boolean) -> Unit,
    onSendToRawBoy: (List<PhotoWithCull>) -> Unit,
    onSendToRawBoyAuto: (List<PhotoWithCull>) -> Unit,
    onShare: (List<PhotoWithCull>) -> Unit,
    onMoveRejectsToBin: () -> Unit,
    onRestoreFromBin: () -> Unit,
    onOpenSettings: () -> Unit,
    onClearStatus: () -> Unit,
) {
    val snackbarHostState = remember { SnackbarHostState() }
    LaunchedEffect(state.statusMessage) {
        val msg = state.statusMessage ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(msg)
        onClearStatus()
    }

    val selecting = state.selectedIds.isNotEmpty()
    BackHandler(enabled = selecting, onBack = onClearSelection)
    val selectedPhotos = remember(state.selectedIds, state.allPhotos) {
        state.allPhotos.filter { it.id in state.selectedIds }
    }
    var menuExpanded by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = DarkroomColours.InkBlack,
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = DarkroomColours.GraphiteSurface,
                    titleContentColor = DarkroomColours.PaperWhite,
                    actionIconContentColor = DarkroomColours.PaperWhite,
                    navigationIconContentColor = DarkroomColours.PaperWhite,
                ),
                navigationIcon = {
                    if (selecting) {
                        IconButton(onClick = onClearSelection) {
                            Icon(Icons.Default.Close, contentDescription = "Clear selection")
                        }
                    } else if (!isExpanded) {
                        IconButton(onClick = onPickFolder) {
                            Icon(Icons.Default.FolderOpen, contentDescription = "Open folder")
                        }
                    }
                },
                title = {
                    if (selecting) {
                        Text("${state.selectedIds.size} selected", fontSize = 16.sp, fontWeight = FontWeight.Medium)
                    } else {
                        Column {
                            Text(
                                state.activeSource?.label ?: "RawBoy Viewer",
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                fontSize = 17.sp,
                                fontWeight = FontWeight.SemiBold,
                            )
                            if (state.activeSource != null) {
                                Text(
                                    "${state.visiblePhotos.size} of ${state.allPhotos.size} · ${if (state.prefs.sort == PhotoSort.DATE) "Date" else "Name"}",
                                    fontSize = 11.sp,
                                    color = DarkroomColours.AshMuted,
                                )
                            }
                        }
                    }
                },
                actions = {
                    if (selecting) {
                        IconButton(onClick = { onSendToRawBoyAuto(selectedPhotos) }) {
                            Icon(Icons.Default.Send, contentDescription = "Send to RawBoy Auto", tint = DarkroomColours.SafelightAmber)
                        }
                        IconButton(onClick = { onShare(selectedPhotos) }) {
                            Icon(Icons.Default.Share, contentDescription = "Share")
                        }
                        TextButton(onClick = onSelectAll) { Text("All") }
                    } else {
                        if (state.canUndo) {
                            IconButton(onClick = onUndo) {
                                Icon(Icons.Default.Undo, contentDescription = "Undo")
                            }
                        }
                        IconButton(onClick = onToggleSort) {
                            Icon(Icons.Default.Sort, contentDescription = "Sort")
                        }
                        IconButton(onClick = onRefresh) {
                            Icon(Icons.Default.Refresh, contentDescription = "Reload folder")
                        }
                        Box {
                            IconButton(onClick = { menuExpanded = true }) {
                                Icon(Icons.Default.MoreVert, contentDescription = "Menu")
                            }
                            DropdownMenu(
                                expanded = menuExpanded,
                                onDismissRequest = { menuExpanded = false },
                                containerColor = DarkroomColours.GraphiteRaised,
                            ) {
                                if (state.visiblePhotos.isNotEmpty()) {
                                    DropdownMenuItem(
                                        text = {
                                            val label = if (state.filter == FlagFilter.PICKS) "Send Picks to RawBoy Auto" else "Send visible to RawBoy Auto"
                                            Text(label)
                                        },
                                        onClick = {
                                            menuExpanded = false
                                            onSendToRawBoyAuto(state.visiblePhotos)
                                        },
                                    )
                                }
                                DropdownMenuItem(
                                    text = {
                                        val suffix = if (state.unsyncedXmpCount > 0) " (${state.unsyncedXmpCount})" else ""
                                        Text("Write ratings to XMP$suffix")
                                    },
                                    onClick = {
                                        menuExpanded = false
                                        onWriteXmp(false)
                                    },
                                )
                                if (state.prefs.enableBinOption) {
                                    DropdownMenuItem(
                                        text = { Text("Move rejects to _bin") },
                                        leadingIcon = { Icon(Icons.Default.DeleteOutline, contentDescription = null) },
                                        onClick = {
                                            menuExpanded = false
                                            onMoveRejectsToBin()
                                        },
                                    )
                                    if (state.binnedCount > 0) {
                                        DropdownMenuItem(
                                            text = { Text("Restore from _bin (${state.binnedCount})") },
                                            leadingIcon = { Icon(Icons.Default.RestoreFromTrash, contentDescription = null) },
                                            onClick = {
                                                menuExpanded = false
                                                onRestoreFromBin()
                                            },
                                        )
                                    }
                                }
                                HorizontalDivider(color = DarkroomColours.Hairline)
                                DropdownMenuItem(
                                    text = { Text("Settings") },
                                    leadingIcon = { Icon(Icons.Default.Settings, contentDescription = null) },
                                    onClick = {
                                        menuExpanded = false
                                        onOpenSettings()
                                    },
                                )
                            }
                        }
                    }
                },
            )
        },
        bottomBar = {
            if (selecting) {
                SelectionActionBar(
                    selectedCount = selectedPhotos.size,
                    rawBoyInstalled = state.rawBoyInstalled,
                    onRate = onRateSelected,
                    onPick = { onFlagSelected(Flag.PICK) },
                    onReject = { onFlagSelected(Flag.REJECT) },
                    onSendToRawBoy = { onSendToRawBoy(selectedPhotos) },
                    onSendToAuto = { onSendToRawBoyAuto(selectedPhotos) },
                    onWriteXmp = { onWriteXmp(true) },
                )
            }
        },
    ) { padding ->
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            if (isExpanded) {
                TabletFolderSidebar(
                    sources = state.sources,
                    activeSourceId = state.activeSource?.id,
                    onPickFolder = onPickFolder,
                    onSelectSource = onSelectSource,
                )
                VerticalDivider(color = DarkroomColours.Hairline, thickness = 1.dp)
            }

            Column(modifier = Modifier.weight(1f).fillMaxHeight()) {
                if (state.isScanning) {
                    LinearProgressIndicator(
                        modifier = Modifier.fillMaxWidth(),
                        color = DarkroomColours.SafelightAmber,
                        trackColor = DarkroomColours.GraphiteRaised,
                    )
                }

                if (state.activeSource != null) {
                    FilterStrip(
                        filter = state.filter,
                        minStars = state.minStars,
                        counts = state.filterCounts,
                        unsyncedXmpCount = state.unsyncedXmpCount,
                        onSetFilter = onSetFilter,
                        onSetMinStars = onSetMinStars,
                        onWriteXmp = { onWriteXmp(false) },
                    )
                }

                if (state.activeSource == null) {
                    EmptyFolderState(onOpenPictures = onOpenPictures, onPickFolder = onPickFolder)
                } else if (state.visiblePhotos.isEmpty() && !state.isScanning) {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            if (state.allPhotos.isEmpty()) "No photos found in this folder"
                            else "No photos match the current filter",
                            color = DarkroomColours.AshMuted,
                        )
                    }
                } else {
                    val groupedByFolder = remember(state.visiblePhotos) {
                        state.visiblePhotos
                            .groupBy { it.folderPath }
                            .entries
                            .sortedWith { a, b ->
                                when {
                                    a.key.isEmpty() && b.key.isEmpty() -> 0
                                    a.key.isEmpty() -> -1
                                    b.key.isEmpty() -> 1
                                    else -> NaturalOrder.compare(a.key, b.key)
                                }
                            }
                    }
                    val hasSubfolders = groupedByFolder.size > 1 || groupedByFolder.any { it.key.isNotEmpty() }
                    val columns = if (isExpanded) GridCells.Adaptive(160.dp) else GridCells.Adaptive(112.dp)
                    LazyVerticalGrid(
                        columns = columns,
                        contentPadding = PaddingValues(6.dp),
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        if (!hasSubfolders) {
                            items(state.visiblePhotos, key = { it.id }) { photo ->
                                PhotoGridCell(
                                    photo = photo,
                                    photoSource = photoSource,
                                    images = images,
                                    selected = photo.id in state.selectedIds,
                                    selecting = selecting,
                                    onClick = {
                                        if (selecting) onToggleSelect(photo.id) else onOpenPhoto(photo.id)
                                    },
                                    onLongClick = { onToggleSelect(photo.id) },
                                )
                            }
                        } else {
                            if (groupedByFolder.size > 1) {
                                item(key = "fold_all_bar", span = { GridItemSpan(maxLineSpan) }) {
                                    val allCollapsed = groupedByFolder.all { it.key in state.collapsedFolders }
                                    Row(
                                        modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
                                        horizontalArrangement = Arrangement.End,
                                    ) {
                                        TextButton(onClick = { onSetAllFoldersCollapsed(!allCollapsed) }) {
                                            Text(
                                                if (allCollapsed) "Unfold all (${groupedByFolder.size})" else "Fold all",
                                                fontSize = 12.sp,
                                                color = DarkroomColours.AshMuted,
                                            )
                                        }
                                    }
                                }
                            }
                            for ((folder, folderPhotos) in groupedByFolder) {
                                val collapsed = folder in state.collapsedFolders
                                val folderLabel = folder.ifEmpty { state.activeSource?.label ?: "Root" }
                                val selectedInFolder = folderPhotos.count { it.id in state.selectedIds }
                                item(key = "hdr:$folder", span = { GridItemSpan(maxLineSpan) }) {
                                    SubfolderSectionHeader(
                                        label = folderLabel,
                                        count = folderPhotos.size,
                                        selectedCount = selectedInFolder,
                                        collapsed = collapsed,
                                        onToggleCollapse = { onToggleFolderCollapsed(folder) },
                                        onLongPress = { onToggleSelectFolder(folder) },
                                    )
                                }
                                if (!collapsed) {
                                    items(folderPhotos, key = { it.id }) { photo ->
                                        PhotoGridCell(
                                            photo = photo,
                                            photoSource = photoSource,
                                            images = images,
                                            selected = photo.id in state.selectedIds,
                                            selecting = selecting,
                                            onClick = {
                                                if (selecting) onToggleSelect(photo.id) else onOpenPhoto(photo.id)
                                            },
                                            onLongClick = { onToggleSelect(photo.id) },
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TabletFolderSidebar(
    sources: List<SourceEntity>,
    activeSourceId: Long?,
    onPickFolder: () -> Unit,
    onSelectSource: (SourceEntity) -> Unit,
) {
    Column(
        modifier = Modifier
            .width(240.dp)
            .fillMaxHeight()
            .background(DarkroomColours.GraphiteSurface)
            .padding(12.dp),
    ) {
        Text("Folders", fontSize = 13.sp, color = DarkroomColours.AshMuted, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(8.dp))
        Button(
            onClick = onPickFolder,
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(
                containerColor = DarkroomColours.SafelightAmber,
                contentColor = DarkroomColours.AmberInk,
            ),
            shape = RoundedCornerShape(8.dp),
        ) {
            Icon(Icons.Default.FolderOpen, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text("Open folder")
        }
        Spacer(Modifier.height(12.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            items(sources, key = { it.id }) { src ->
                val active = src.id == activeSourceId
                Surface(
                    onClick = { onSelectSource(src) },
                    color = if (active) DarkroomColours.GraphiteRaised else Color.Transparent,
                    shape = RoundedCornerShape(8.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 10.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            Icons.Default.FolderOpen,
                            contentDescription = null,
                            tint = if (active) DarkroomColours.SafelightAmber else DarkroomColours.AshMuted,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(Modifier.width(8.dp))
                        Text(
                            src.label,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            color = if (active) DarkroomColours.PaperWhite else DarkroomColours.AshMuted,
                            fontSize = 14.sp,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun FilterStrip(
    filter: FlagFilter,
    minStars: Int,
    counts: Map<FlagFilter, Int>,
    unsyncedXmpCount: Int,
    onSetFilter: (FlagFilter) -> Unit,
    onSetMinStars: (Int) -> Unit,
    onWriteXmp: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(DarkroomColours.GraphiteSurface)
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 10.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val labels = listOf(
            FlagFilter.ALL to "All",
            FlagFilter.PICKS to "Picks",
            FlagFilter.UNFLAGGED to "Unflagged",
            FlagFilter.REJECTS to "Rejects",
        )
        for ((f, label) in labels) {
            val count = counts[f] ?: 0
            FilterChip(
                selected = filter == f,
                onClick = { onSetFilter(f) },
                label = { Text("$label $count", fontSize = 12.sp) },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = DarkroomColours.SafelightAmber,
                    selectedLabelColor = DarkroomColours.AmberInk,
                    containerColor = DarkroomColours.GraphiteRaised,
                    labelColor = DarkroomColours.PaperWhite,
                ),
            )
        }
        Spacer(Modifier.width(4.dp))
        for (s in 1..5) {
            FilterChip(
                selected = minStars == s,
                onClick = { onSetMinStars(s) },
                label = { Text("$s★", fontSize = 12.sp) },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = DarkroomColours.SafelightAmber,
                    selectedLabelColor = DarkroomColours.AmberInk,
                    containerColor = DarkroomColours.GraphiteRaised,
                    labelColor = DarkroomColours.AshMuted,
                ),
            )
        }
        if (unsyncedXmpCount > 0) {
            Spacer(Modifier.width(6.dp))
            TextButton(onClick = onWriteXmp) {
                Text("Write XMP ($unsyncedXmpCount)", fontSize = 12.sp, color = DarkroomColours.SafelightAmber)
            }
        }
    }
    HorizontalDivider(color = DarkroomColours.Hairline, thickness = 1.dp)
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PhotoGridCell(
    photo: PhotoWithCull,
    photoSource: PhotoSource?,
    images: ImageRepository,
    selected: Boolean,
    selecting: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    val thumb by produceState<Bitmap?>(initialValue = null, key1 = photo.id, key2 = photoSource?.rootUri) {
        value = if (photoSource != null) images.loadThumbnail(photoSource, photo) else null
    }
    val borderColor = when {
        selected -> DarkroomColours.SafelightAmber
        photo.effectiveFlag == Flag.PICK.dbValue -> DarkroomColours.SafelightAmber.copy(alpha = 0.55f)
        photo.effectiveFlag == Flag.REJECT.dbValue -> DarkroomColours.WarningRed.copy(alpha = 0.55f)
        else -> Color.Transparent
    }

    Box(
        modifier = Modifier
            .aspectRatio(1f)
            .clip(RoundedCornerShape(6.dp))
            .background(DarkroomColours.GraphiteRaised)
            .border(if (selected) 2.5.dp else 1.dp, borderColor, RoundedCornerShape(6.dp))
            .combinedClickable(onClick = onClick, onLongClick = onLongClick),
    ) {
        if (thumb != null) {
            Image(
                bitmap = thumb!!.asImageBitmap(),
                contentDescription = photo.relPath,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            Text(
                photo.relPath.substringAfterLast('.', "").uppercase(),
                color = DarkroomColours.AshMuted,
                fontSize = 11.sp,
                modifier = Modifier.align(Alignment.Center),
            )
        }

        // Top-left: RAW / RAW+JPG / VIDEO badge
        val fileType = PhotoFileType.of(photo.fileName)
        if (fileType == PhotoFileType.RAW || fileType == PhotoFileType.VIDEO) {
            val badge = when (fileType) {
                PhotoFileType.VIDEO -> "VIDEO"
                PhotoFileType.RAW -> if (photo.companionNames.isNotEmpty()) "RAW+JPG" else "RAW"
                else -> ""
            }
            Text(
                badge,
                color = DarkroomColours.PaperWhite,
                fontSize = 9.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(4.dp)
                    .background(Color.Black.copy(alpha = 0.65f), RoundedCornerShape(4.dp))
                    .padding(horizontal = 4.dp, vertical = 1.dp),
            )
        }

        if (fileType == PhotoFileType.VIDEO) {
            Box(
                modifier = Modifier
                    .align(Alignment.Center)
                    .size(34.dp)
                    .background(Color.Black.copy(alpha = 0.55f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Default.PlayArrow,
                    contentDescription = "Video",
                    tint = DarkroomColours.PaperWhite,
                    modifier = Modifier.size(22.dp),
                )
            }
        }

        // Top-right: selection check or unsynced XMP dot
        if (selecting) {
            Icon(
                Icons.Default.CheckCircle,
                contentDescription = null,
                tint = if (selected) DarkroomColours.SafelightAmber else Color.White.copy(alpha = 0.35f),
                modifier = Modifier.align(Alignment.TopEnd).padding(4.dp).size(20.dp),
            )
        } else if (photo.needsXmpWrite) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(6.dp)
                    .size(7.dp)
                    .background(DarkroomColours.SafelightAmber, CircleShape),
            )
        }

        // Bottom overlay: flag + stars + sent badge
        if (photo.effectiveStars > 0 || photo.effectiveFlag != 0 || photo.sentToAutoCount > 0) {
            Row(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .background(Color.Black.copy(alpha = 0.6f))
                    .padding(horizontal = 5.dp, vertical = 3.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    when (photo.effectiveFlag) {
                        Flag.PICK.dbValue -> Text("P", color = DarkroomColours.SafelightAmber, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                        Flag.REJECT.dbValue -> Text("X", color = DarkroomColours.WarningRed, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                    }
                    if (photo.effectiveStars > 0) {
                        Text(
                            "★".repeat(photo.effectiveStars),
                            color = DarkroomColours.SafelightAmber,
                            fontSize = 10.sp,
                        )
                    }
                }
                if (photo.sentToAutoCount > 0) {
                    Text("AUTO", color = DarkroomColours.AshMuted, fontSize = 9.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

@Composable
private fun SelectionActionBar(
    selectedCount: Int,
    rawBoyInstalled: Boolean,
    onRate: (Int) -> Unit,
    onPick: () -> Unit,
    onReject: () -> Unit,
    onSendToRawBoy: () -> Unit,
    onSendToAuto: () -> Unit,
    onWriteXmp: () -> Unit,
) {
    Surface(
        color = DarkroomColours.GraphiteSurface,
        tonalElevation = 0.dp,
    ) {
        Column(modifier = Modifier.navigationBarsPadding()) {
            HorizontalDivider(color = DarkroomColours.Hairline)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 8.dp, vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onPick) { Text("Pick", color = DarkroomColours.SafelightAmber) }
                TextButton(onClick = onReject) { Text("Reject", color = DarkroomColours.WarningRed) }
                for (s in 1..5) {
                    IconButton(onClick = { onRate(s) }, modifier = Modifier.size(36.dp)) {
                        Icon(Icons.Default.Star, contentDescription = "$s stars", tint = DarkroomColours.SafelightAmber, modifier = Modifier.size(18.dp))
                    }
                }
                if (rawBoyInstalled && selectedCount == 1) {
                    TextButton(onClick = onSendToRawBoy) { Text("RawBoy", color = DarkroomColours.PaperWhite) }
                }
                TextButton(onClick = onSendToAuto) { Text("RawBoy Auto", color = DarkroomColours.SafelightAmber) }
                TextButton(onClick = onWriteXmp) { Text("Write XMP", color = DarkroomColours.AshMuted) }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SubfolderSectionHeader(
    label: String,
    count: Int,
    selectedCount: Int,
    collapsed: Boolean,
    onToggleCollapse: () -> Unit,
    onLongPress: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 6.dp, bottom = 2.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(DarkroomColours.GraphiteSurface)
            .border(1.dp, DarkroomColours.Hairline, RoundedCornerShape(8.dp))
            .combinedClickable(onClick = onToggleCollapse, onLongClick = onLongPress)
            .padding(horizontal = 10.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            if (collapsed) Icons.Default.ChevronRight else Icons.Default.ExpandMore,
            contentDescription = if (collapsed) "Unfold" else "Fold",
            tint = DarkroomColours.AshMuted,
            modifier = Modifier.size(20.dp),
        )
        Spacer(Modifier.width(6.dp))
        Icon(
            Icons.Default.Folder,
            contentDescription = null,
            tint = DarkroomColours.SafelightAmber,
            modifier = Modifier.size(18.dp),
        )
        Spacer(Modifier.width(8.dp))
        Text(
            label,
            color = DarkroomColours.PaperWhite,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        if (selectedCount > 0) {
            Text(
                "$selectedCount / $count",
                color = DarkroomColours.SafelightAmber,
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
            )
        } else {
            Text(
                "$count",
                color = DarkroomColours.AshMuted,
                fontSize = 12.sp,
            )
        }
    }
}

@Composable
private fun EmptyFolderState(
    onOpenPictures: () -> Unit,
    onPickFolder: () -> Unit,
) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(24.dp)) {
            Icon(
                Icons.Default.FolderOpen,
                contentDescription = null,
                tint = DarkroomColours.SafelightAmber,
                modifier = Modifier.size(56.dp),
            )
            Spacer(Modifier.height(12.dp))
            Text("Open a folder of photos", fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = DarkroomColours.PaperWhite)
            Spacer(Modifier.height(6.dp))
            Text(
                "Browse camera raws fast from embedded previews, cull locally, and send keepers straight to RawBoy Auto.",
                fontSize = 13.sp,
                color = DarkroomColours.AshMuted,
            )
            Spacer(Modifier.height(18.dp))
            Button(
                onClick = onOpenPictures,
                colors = ButtonDefaults.buttonColors(
                    containerColor = DarkroomColours.SafelightAmber,
                    contentColor = DarkroomColours.AmberInk,
                ),
                shape = RoundedCornerShape(8.dp),
            ) {
                Text("Open Pictures & DCIM")
            }
            Spacer(Modifier.height(8.dp))
            TextButton(onClick = onPickFolder) {
                Text("Choose another folder…", color = DarkroomColours.PaperWhite)
            }
        }
    }
}
