package app.rawboy.viewer

import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.material3.windowsizeclass.ExperimentalMaterial3WindowSizeClassApi
import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.compose.material3.windowsizeclass.calculateWindowSizeClass
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
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
                val isExpanded = windowSize.widthSizeClass != WindowWidthSizeClass.Compact
                val state by viewModel.state.collectAsState()
                val photoSource by viewModel.activePhotoSource.collectAsState()

                val folderPicker = rememberLauncherForActivityResult(
                    contract = ActivityResultContracts.OpenDocumentTree(),
                ) { uri: Uri? ->
                    if (uri != null) viewModel.openFolder(uri, persistPermission = true)
                }

                val viewerId = state.viewerPhotoId
                if (viewerId != null && photoSource != null && state.visiblePhotos.isNotEmpty()) {
                    FullScreenViewer(
                        photos = state.visiblePhotos,
                        initialPhotoId = viewerId,
                        photoSource = photoSource!!,
                        images = viewModel.images,
                        isExpanded = isExpanded,
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
                } else {
                    BrowserScreen(
                        state = state,
                        photoSource = photoSource,
                        images = viewModel.images,
                        isExpanded = isExpanded,
                        onPickFolder = { folderPicker.launch(null) },
                        onSelectSource = { src -> viewModel.openFolder(Uri.parse(src.rootUri), persistPermission = false) },
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
