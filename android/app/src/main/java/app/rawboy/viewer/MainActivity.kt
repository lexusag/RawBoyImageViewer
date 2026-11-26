package app.rawboy.viewer

import android.Manifest
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.windowsizeclass.ExperimentalMaterial3WindowSizeClassApi
import androidx.compose.material3.windowsizeclass.WindowHeightSizeClass
import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.compose.material3.windowsizeclass.calculateWindowSizeClass
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import app.rawboy.viewer.handoff.AutoImportMode
import app.rawboy.viewer.ui.BrowserScreen
import app.rawboy.viewer.ui.FullScreenViewer
import app.rawboy.viewer.ui.RawBoyViewerTheme
import app.rawboy.viewer.ui.SendToAutoSheet
import app.rawboy.viewer.ui.SettingsDialog
import app.rawboy.viewer.ui.ViewerViewModel
import app.rawboy.viewer.ui.XmpConflictDialog
import app.rawboy.viewer.ui.XmpResultDialog

class MainActivity : ComponentActivity() {
    private val viewModel: ViewerViewModel by viewModels()

    @OptIn(ExperimentalMaterial3WindowSizeClassApi::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        setContent {
            RawBoyViewerTheme {
                val windowSize = calculateWindowSizeClass(this)
                val isCompactHeight = windowSize.heightSizeClass == WindowHeightSizeClass.Compact
                val isExpanded = windowSize.widthSizeClass != WindowWidthSizeClass.Compact && !isCompactHeight
                val state by viewModel.state.collectAsState()
                val photoSource by viewModel.activePhotoSource.collectAsState()

                val picturesInitialUri = Uri.parse("content://com.android.externalstorage.documents/document/primary:Pictures")

                val folderPicker = rememberLauncherForActivityResult(
                    contract = ActivityResultContracts.OpenDocumentTree(),
                ) { uri: Uri? ->
                    if (uri != null) viewModel.openFolder(uri, persistPermission = true)
                }

                val defaultFolderPicker = rememberLauncherForActivityResult(
                    contract = ActivityResultContracts.OpenDocumentTree(),
                ) { uri: Uri? ->
                    if (uri != null) viewModel.setDefaultFolder(uri)
                }

                val mediaPermissionLauncher = rememberLauncherForActivityResult(
                    contract = ActivityResultContracts.RequestMultiplePermissions(),
                ) { results ->
                    if (results.values.any { it }) {
                        viewModel.openPicturesGallery()
                    }
                }

                fun openPicturesWithPermission() {
                    if (viewModel.hasMediaPermission()) {
                        viewModel.openPicturesGallery()
                    } else {
                        val perms = if (Build.VERSION.SDK_INT >= 33) {
                            arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO)
                        } else {
                            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
                        }
                        mediaPermissionLauncher.launch(perms)
                    }
                }

                var askedInitialPermission by rememberSaveable { mutableStateOf(false) }
                LaunchedEffect(state.prefsLoaded, state.activeSource, state.prefs.lastFolderUri) {
                    if (state.prefsLoaded && !askedInitialPermission && state.activeSource == null && state.prefs.lastFolderUri == null) {
                        askedInitialPermission = true
                        openPicturesWithPermission()
                    }
                }

                // Keep BrowserScreen mounted underneath FullScreenViewer so LazyVerticalGrid keeps its exact scroll offset.
                Box(modifier = Modifier.fillMaxSize()) {
                    BrowserScreen(
                        state = state,
                        photoSource = photoSource,
                        images = viewModel.images,
                        isExpanded = isExpanded,
                        onPickFolder = { folderPicker.launch(picturesInitialUri) },
                        onOpenPictures = { openPicturesWithPermission() },
                        onSelectSource = viewModel::openSource,
                        onOpenPhoto = viewModel::openViewer,
                        onToggleSelect = viewModel::toggleSelect,
                        onSelectAll = viewModel::selectAllVisible,
                        onClearSelection = viewModel::clearSelection,
                        onToggleFolderCollapsed = viewModel::toggleFolderCollapsed,
                        onSetAllFoldersCollapsed = viewModel::setAllFoldersCollapsed,
                        onToggleSelectFolder = viewModel::toggleSelectFolder,
                        onSetFilter = viewModel::setFilter,
                        onSetMinStars = viewModel::setMinStars,
                        onToggleSort = viewModel::toggleSort,
                        onRefresh = viewModel::refreshFolder,
                        onRateSelected = { s -> viewModel.ratePhotos(state.selectedIds.toList(), s) },
                        onFlagSelected = { f -> viewModel.flagPhotos(state.selectedIds.toList(), f) },
                        onUndo = viewModel::undo,
                        onWriteXmp = viewModel::requestWriteXmp,
                        onSendToRawBoy = viewModel::sendToRawBoy,
                        onSendToRawBoyAuto = viewModel::openAutoSendSheet,
                        onShare = viewModel::shareTargets,
                        onMoveRejectsToBin = viewModel::moveRejectsToBin,
                        onRestoreFromBin = viewModel::restoreFromBin,
                        onOpenSettings = viewModel::openSettings,
                        onClearStatus = viewModel::clearStatus,
                    )

                    val viewerId = state.viewerPhotoId
                    if (viewerId != null && photoSource != null && state.visiblePhotos.isNotEmpty()) {
                        FullScreenViewer(
                            photos = state.visiblePhotos,
                            initialPhotoId = viewerId,
                            photoSource = photoSource!!,
                            images = viewModel.images,
                            isExpanded = isExpanded,
                            overlayChrome = isCompactHeight,
                            autoAdvance = state.prefs.autoAdvanceAfterRating,
                            canUndo = state.canUndo,
                            rawBoyInstalled = state.rawBoyInstalled,
                            onClose = viewModel::closeViewer,
                            onRate = { id, stars -> viewModel.ratePhotos(listOf(id), stars) },
                            onFlag = { id, flag -> viewModel.flagPhotos(listOf(id), flag) },
                            onUndo = viewModel::undo,
                            onPrefetch = viewModel::prefetchAround,
                            onSendToRawBoy = { photo -> viewModel.sendToRawBoy(listOf(photo)) },
                            onSendToRawBoyAuto = { photo -> viewModel.openAutoSendSheet(listOf(photo)) },
                        )
                    }
                }

                state.pendingConflicts?.let { conflicts ->
                    XmpConflictDialog(
                        conflicts = conflicts,
                        onResolve = viewModel::resolveXmpConflicts,
                        onDismiss = viewModel::dismissXmpDialogs,
                    )
                }

                state.xmpResult?.let { result ->
                    XmpResultDialog(
                        result = result,
                        onDismiss = viewModel::dismissXmpDialogs,
                    )
                }

                if (state.showAutoSendSheet) {
                    SendToAutoSheet(
                        photoCount = state.autoSendTargets.size,
                        rawBoyAutoInstalled = state.rawBoyAutoInstalled,
                        initialMode = AutoImportMode.fromRaw(state.prefs.lastAutoMode),
                        initialIncludeJpegs = state.prefs.includeJpegsInBatch,
                        onSend = viewModel::sendToRawBoyAuto,
                        onDismiss = viewModel::dismissAutoSendSheet,
                    )
                }

                if (state.showSettings) {
                    SettingsDialog(
                        prefs = state.prefs,
                        onStartupMode = viewModel::setStartupMode,
                        onPickDefaultFolder = { defaultFolderPicker.launch(picturesInitialUri) },
                        onGroupBySubfolders = viewModel::setGroupBySubfolders,
                        onAutoAdvance = viewModel::setAutoAdvance,
                        onWriteXmpBeforeSend = viewModel::setWriteXmpBeforeSend,
                        onIncludeJpegs = viewModel::setIncludeJpegsInBatch,
                        onEnableBin = viewModel::setEnableBin,
                        onDismiss = viewModel::dismissSettings,
                    )
                }
            }
        }
    }
}
