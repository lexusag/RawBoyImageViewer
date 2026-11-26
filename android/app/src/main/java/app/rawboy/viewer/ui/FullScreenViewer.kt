package app.rawboy.viewer.ui

import android.graphics.Bitmap
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.displayCutoutPadding
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.automirrored.filled.VolumeOff
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isMetaPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import app.rawboy.viewer.core.Flag
import app.rawboy.viewer.core.Histogram
import app.rawboy.viewer.core.PhotoFileType
import app.rawboy.viewer.data.PhotoWithCull
import app.rawboy.viewer.imaging.ImageRepository
import app.rawboy.viewer.imaging.PhotoDetails
import app.rawboy.viewer.sources.PhotoSource
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FullScreenViewer(
    photos: List<PhotoWithCull>,
    initialPhotoId: Long,
    photoSource: PhotoSource,
    images: ImageRepository,
    isExpanded: Boolean,
    overlayChrome: Boolean = false,
    autoAdvance: Boolean,
    canUndo: Boolean,
    rawBoyInstalled: Boolean,
    onClose: () -> Unit,
    onRate: (Long, Int) -> Unit,
    onFlag: (Long, Flag?) -> Unit,
    onUndo: () -> Unit,
    onPrefetch: (Int, Boolean) -> Unit,
    onSendToRawBoy: (PhotoWithCull) -> Unit,
    onSendToRawBoyAuto: (PhotoWithCull) -> Unit,
    onDelete: (PhotoWithCull) -> Unit,
) {
    BackHandler(onBack = onClose)

    val startIndex = remember(initialPhotoId, photos) {
        photos.indexOfFirst { it.id == initialPhotoId }.coerceAtLeast(0)
    }
    val pagerState = rememberPagerState(initialPage = startIndex, pageCount = { photos.size })
    val scope = rememberCoroutineScope()
    var showChrome by remember { mutableStateOf(true) }
    var showDetailsSheet by remember { mutableStateOf(false) }
    var lastPage by remember { mutableStateOf(startIndex) }
    var isZoomed by remember { mutableStateOf(false) }

    val currentPhoto = photos.getOrNull(pagerState.currentPage)
    LaunchedEffect(pagerState.currentPage, photos.size) {
        val forward = pagerState.currentPage >= lastPage
        lastPage = pagerState.currentPage
        isZoomed = false
        onPrefetch(pagerState.currentPage, forward)
    }

    val focusRequester = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focusRequester.requestFocus() } }

    fun advanceIfWanted() {
        if (autoAdvance && pagerState.currentPage + 1 < photos.size) {
            scope.launch { pagerState.animateScrollToPage(pagerState.currentPage + 1) }
        }
    }

    val currentBitmap by produceState<Bitmap?>(initialValue = null, key1 = currentPhoto?.id) {
        value = currentPhoto?.let { images.loadViewerBitmap(photoSource, it) }
    }
    val details by produceState<PhotoDetails?>(initialValue = null, key1 = currentPhoto?.id, key2 = currentBitmap) {
        value = currentPhoto?.let { images.loadDetails(photoSource, it, currentBitmap) }
    }

    Row(
        modifier = Modifier
            .fillMaxSize()
            .background(DarkroomColours.InkBlack)
            .focusRequester(focusRequester)
            .focusable()
            .onPreviewKeyEvent { ev ->
                if (ev.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                val photo = currentPhoto ?: return@onPreviewKeyEvent false
                when (ev.key) {
                    Key.Escape -> { onClose(); true }
                    Key.DirectionRight, Key.Spacebar -> {
                        if (pagerState.currentPage + 1 < photos.size) {
                            scope.launch { pagerState.animateScrollToPage(pagerState.currentPage + 1) }
                        }
                        true
                    }
                    Key.DirectionLeft -> {
                        if (pagerState.currentPage > 0) {
                            scope.launch { pagerState.animateScrollToPage(pagerState.currentPage - 1) }
                        }
                        true
                    }
                    Key.One -> { onRate(photo.id, 1); advanceIfWanted(); true }
                    Key.Two -> { onRate(photo.id, 2); advanceIfWanted(); true }
                    Key.Three -> { onRate(photo.id, 3); advanceIfWanted(); true }
                    Key.Four -> { onRate(photo.id, 4); advanceIfWanted(); true }
                    Key.Five -> { onRate(photo.id, 5); advanceIfWanted(); true }
                    Key.Zero -> { onRate(photo.id, 0); true }
                    Key.P -> { onFlag(photo.id, Flag.PICK); advanceIfWanted(); true }
                    Key.X -> { onFlag(photo.id, Flag.REJECT); advanceIfWanted(); true }
                    Key.U -> { onFlag(photo.id, null); true }
                    Key.I -> { showDetailsSheet = !showDetailsSheet; true }
                    Key.Z -> if (ev.isCtrlPressed || ev.isMetaPressed) { onUndo(); true } else false
                    else -> false
                }
            },
    ) {
        val topBar: @Composable () -> Unit = {
            if (showChrome && currentPhoto != null) {
                Surface(
                    color = if (overlayChrome) DarkroomColours.GraphiteSurface.copy(alpha = 0.78f) else DarkroomColours.GraphiteSurface,
                ) {
                    Column(
                        modifier = Modifier
                            .statusBarsPadding()
                            .displayCutoutPadding(),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 2.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            IconButton(onClick = onClose) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back", tint = DarkroomColours.PaperWhite)
                            }
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    currentPhoto.fileName,
                                    color = DarkroomColours.PaperWhite,
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Medium,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                                val subtitle = if (currentPhoto.folderPath.isNotEmpty()) {
                                    "${currentPhoto.folderPath} · ${pagerState.currentPage + 1} / ${photos.size}"
                                } else {
                                    "${pagerState.currentPage + 1} / ${photos.size}"
                                }
                                Text(
                                    subtitle,
                                    color = DarkroomColours.AshMuted,
                                    fontSize = 11.sp,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            }
                            if (canUndo) {
                                IconButton(onClick = onUndo) {
                                    Icon(Icons.AutoMirrored.Filled.Undo, contentDescription = "Undo", tint = DarkroomColours.PaperWhite)
                                }
                            }
                            if (rawBoyInstalled) {
                                TextButton(onClick = { onSendToRawBoy(currentPhoto) }) {
                                    Text("RawBoy", color = DarkroomColours.PaperWhite, fontSize = 12.sp)
                                }
                            }
                            IconButton(onClick = { onSendToRawBoyAuto(currentPhoto) }) {
                                Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Send to RawBoy Auto", tint = DarkroomColours.SafelightAmber)
                            }
                            IconButton(onClick = { onDelete(currentPhoto) }) {
                                Icon(Icons.Default.Delete, contentDescription = "Delete", tint = DarkroomColours.WarningRed)
                            }
                            if (!isExpanded) {
                                IconButton(onClick = { showDetailsSheet = true }) {
                                    Icon(Icons.Default.Info, contentDescription = "Details", tint = DarkroomColours.PaperWhite)
                                }
                            }
                        }
                        if (isExpanded) {
                            FilmstripRow(
                                photos = photos,
                                currentIndex = pagerState.currentPage,
                                photoSource = photoSource,
                                images = images,
                                onSelect = { idx -> scope.launch { pagerState.animateScrollToPage(idx) } },
                            )
                        }
                    }
                }
            }
        }

        val bottomBar: @Composable () -> Unit = {
            if (showChrome && currentPhoto != null) {
                ViewerRatingBar(
                    photo = currentPhoto,
                    translucent = overlayChrome,
                    onRate = { s -> onRate(currentPhoto.id, s); advanceIfWanted() },
                    onPick = { onFlag(currentPhoto.id, Flag.PICK); advanceIfWanted() },
                    onReject = { onFlag(currentPhoto.id, Flag.REJECT); advanceIfWanted() },
                )
            }
        }

        var isScrubbing by remember { mutableStateOf(false) }
        val pagerContent: @Composable (Modifier) -> Unit = { mod ->
            HorizontalPager(
                state = pagerState,
                userScrollEnabled = !isZoomed && !isScrubbing,
                modifier = mod,
            ) { page ->
                val photo = photos[page]
                if (PhotoFileType.of(photo.fileName) == PhotoFileType.VIDEO) {
                    VideoPlayerPage(
                        photo = photo,
                        photoSource = photoSource,
                        isActivePage = page == pagerState.currentPage,
                        showChrome = showChrome,
                        onToggleChrome = { showChrome = !showChrome },
                        onScrubbingChanged = { scrubbing -> if (page == pagerState.currentPage) isScrubbing = scrubbing },
                    )
                } else {
                    ZoomablePhotoPage(
                        photo = photo,
                        photoSource = photoSource,
                        images = images,
                        onToggleChrome = { showChrome = !showChrome },
                        onZoomChanged = { zoomed -> if (page == pagerState.currentPage) isZoomed = zoomed },
                    )
                }
            }
        }

        if (overlayChrome) {
            Box(modifier = Modifier.weight(1f).fillMaxHeight()) {
                pagerContent(Modifier.fillMaxSize())
                Box(modifier = Modifier.align(Alignment.TopCenter).fillMaxWidth()) { topBar() }
                Box(modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth()) { bottomBar() }
            }
        } else {
            Column(modifier = Modifier.weight(1f).fillMaxHeight()) {
                topBar()
                Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                    pagerContent(Modifier.fillMaxSize())
                }
                bottomBar()
            }
        }

        // Tablet pinned right details pane
        if (isExpanded && showChrome && currentPhoto != null) {
            VerticalDivider(color = DarkroomColours.Hairline)
            Box(
                modifier = Modifier
                    .width(280.dp)
                    .fillMaxHeight()
                    .background(DarkroomColours.GraphiteSurface)
                    .statusBarsPadding()
                    .navigationBarsPadding()
                    .padding(16.dp),
            ) {
                PhotoDetailsContent(photo = currentPhoto, details = details)
            }
        }
    }

    // Phone bottom sheet for details
    if (!isExpanded && showDetailsSheet && currentPhoto != null) {
        ModalBottomSheet(
            onDismissRequest = { showDetailsSheet = false },
            containerColor = DarkroomColours.GraphiteSurface,
        ) {
            Box(modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
                PhotoDetailsContent(photo = currentPhoto, details = details)
            }
        }
    }
}

@Composable
private fun ZoomablePhotoPage(
    photo: PhotoWithCull,
    photoSource: PhotoSource,
    images: ImageRepository,
    onToggleChrome: () -> Unit,
    onZoomChanged: (Boolean) -> Unit,
) {
    val bmp by produceState<Bitmap?>(initialValue = null, key1 = photo.id) {
        value = images.loadViewerBitmap(photoSource, photo)
    }
    var scale by remember(photo.id) { mutableFloatStateOf(1f) }
    var offset by remember(photo.id) { mutableStateOf(Offset.Zero) }
    var containerSize by remember { mutableStateOf(IntSize.Zero) }

    fun clampOffset(raw: Offset, targetScale: Float): Offset {
        if (targetScale <= 1.02f || containerSize.width == 0 || containerSize.height == 0) return Offset.Zero
        val maxX = (containerSize.width * (targetScale - 1f) / 2f).coerceAtLeast(0f)
        val maxY = (containerSize.height * (targetScale - 1f) / 2f).coerceAtLeast(0f)
        return Offset(raw.x.coerceIn(-maxX, maxX), raw.y.coerceIn(-maxY, maxY))
    }

    fun zoomAround(focal: Offset, targetScale: Float, pan: Offset = Offset.Zero) {
        val clampedScale = targetScale.coerceIn(1f, 6f)
        if (clampedScale <= 1.02f) {
            scale = 1f
            offset = Offset.Zero
            onZoomChanged(false)
            return
        }
        val center = Offset(containerSize.width / 2f, containerSize.height / 2f)
        val anchor = focal - center
        val ratio = clampedScale / scale
        val nextOffset = anchor - (anchor - offset) * ratio + pan
        scale = clampedScale
        offset = clampOffset(nextOffset, clampedScale)
        onZoomChanged(true)
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .onSizeChanged { containerSize = it }
            .pointerInput(photo.id) {
                detectTapGestures(
                    onTap = { onToggleChrome() },
                    onDoubleTap = { tapOffset ->
                        if (scale > 1.05f) {
                            zoomAround(tapOffset, 1f)
                        } else {
                            zoomAround(tapOffset, 2.5f)
                        }
                    },
                )
            }
            .pointerInput(photo.id) {
                val touchSlop = viewConfiguration.touchSlop
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    var pastSlop = false
                    var totalPan = Offset.Zero
                    do {
                        val event = awaitPointerEvent()
                        val pressed = event.changes.count { it.pressed }
                        val zoomChange = event.calculateZoom()
                        val panChange = event.calculatePan()
                        if (pressed >= 2) {
                            pastSlop = true
                        } else if (scale > 1.02f) {
                            totalPan += panChange
                            if (totalPan.getDistance() > touchSlop) pastSlop = true
                        }
                        if (pastSlop && (pressed >= 2 || scale > 1.02f)) {
                            val centroid = event.calculateCentroid(useCurrent = true)
                            val focal = if (centroid != Offset.Unspecified) {
                                centroid
                            } else {
                                Offset(containerSize.width / 2f, containerSize.height / 2f)
                            }
                            zoomAround(focal, scale * zoomChange, panChange)
                            event.changes.forEach { it.consume() }
                        }
                    } while (event.changes.any { it.pressed })
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        if (bmp != null) {
            Image(
                bitmap = bmp!!.asImageBitmap(),
                contentDescription = photo.relPath,
                contentScale = ContentScale.Fit,
                modifier = Modifier
                    .fillMaxSize()
                    .graphicsLayer(
                        scaleX = scale,
                        scaleY = scale,
                        translationX = offset.x,
                        translationY = offset.y,
                    ),
            )
        } else {
            CircularProgressIndicator(color = DarkroomColours.SafelightAmber)
        }
    }
}

@Composable
private fun VideoPlayerPage(
    photo: PhotoWithCull,
    photoSource: PhotoSource,
    isActivePage: Boolean,
    showChrome: Boolean,
    onToggleChrome: () -> Unit,
    onScrubbingChanged: (Boolean) -> Unit,
) {
    val context = LocalContext.current
    val videoUri = remember(photo.docId, photoSource.rootUri) { photoSource.uriForShare(photo.docId) }
    val player = remember(videoUri) {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(videoUri))
            prepare()
        }
    }

    var isPlaying by remember(videoUri) { mutableStateOf(false) }
    var isMuted by remember(videoUri) { mutableStateOf(false) }
    var durationMs by remember(videoUri) { mutableLongStateOf(0L) }
    var positionMs by remember(videoUri) { mutableLongStateOf(0L) }
    var isDragging by remember(videoUri) { mutableStateOf(false) }
    var dragFraction by remember(videoUri) { mutableFloatStateOf(0f) }

    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(playing: Boolean) {
                isPlaying = playing
            }

            override fun onPlaybackStateChanged(state: Int) {
                if (player.duration > 0L) durationMs = player.duration
                if (state == Player.STATE_ENDED) {
                    isPlaying = false
                }
            }
        }
        player.addListener(listener)
        onDispose {
            onScrubbingChanged(false)
            player.removeListener(listener)
            player.release()
        }
    }

    // Auto-pause when swiping away from this page, auto-play when landing on it.
    LaunchedEffect(isActivePage, player) {
        if (isActivePage) {
            player.playWhenReady = true
        } else {
            player.pause()
        }
    }

    // Poll playback position smoothly while active and not scrubbing.
    LaunchedEffect(player, isActivePage, isDragging) {
        while (isActivePage) {
            if (player.duration > 0L) durationMs = player.duration
            if (!isDragging) positionMs = player.currentPosition.coerceAtLeast(0L)
            delay(150)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(DarkroomColours.InkBlack)
            .pointerInput(photo.id) {
                detectTapGestures(onTap = { onToggleChrome() })
            },
    ) {
        AndroidView(
            factory = { ctx ->
                PlayerView(ctx).apply {
                    useController = false
                    this.player = player
                }
            },
            update = { view ->
                if (view.player !== player) view.player = player
            },
            modifier = Modifier.fillMaxSize(),
        )

        if (showChrome) {
            Column(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .background(Color.Black.copy(alpha = 0.65f))
                    .padding(horizontal = 12.dp, vertical = 6.dp),
            ) {
                val safeDuration = durationMs.coerceAtLeast(1L)
                val sliderValue = if (isDragging) {
                    dragFraction
                } else {
                    (positionMs.toFloat() / safeDuration.toFloat()).coerceIn(0f, 1f)
                }
                val displayedPosMs = if (isDragging) (dragFraction * safeDuration).toLong() else positionMs

                Slider(
                    value = sliderValue,
                    onValueChange = { frac ->
                        if (!isDragging) {
                            isDragging = true
                            onScrubbingChanged(true)
                        }
                        dragFraction = frac
                        if (durationMs > 0L) {
                            player.seekTo((frac * durationMs).toLong())
                        }
                    },
                    onValueChangeFinished = {
                        if (durationMs > 0L) {
                            val target = (dragFraction * durationMs).toLong()
                            player.seekTo(target)
                            positionMs = target
                        }
                        isDragging = false
                        onScrubbingChanged(false)
                    },
                    colors = SliderDefaults.colors(
                        thumbColor = DarkroomColours.SafelightAmber,
                        activeTrackColor = DarkroomColours.SafelightAmber,
                        inactiveTrackColor = DarkroomColours.Hairline,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        IconButton(
                            onClick = {
                                if (player.playbackState == Player.STATE_ENDED) {
                                    player.seekTo(0L)
                                    player.play()
                                } else if (player.isPlaying) {
                                    player.pause()
                                } else {
                                    player.play()
                                }
                            },
                        ) {
                            Icon(
                                if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                                contentDescription = if (isPlaying) "Pause" else "Play",
                                tint = DarkroomColours.PaperWhite,
                            )
                        }
                        Text(
                            "${formatDuration(displayedPosMs)} / ${formatDuration(durationMs)}",
                            color = DarkroomColours.PaperWhite,
                            fontSize = 12.sp,
                        )
                    }
                    IconButton(
                        onClick = {
                            isMuted = !isMuted
                            player.volume = if (isMuted) 0f else 1f
                        },
                    ) {
                        Icon(
                            if (isMuted) Icons.AutoMirrored.Filled.VolumeOff else Icons.AutoMirrored.Filled.VolumeUp,
                            contentDescription = if (isMuted) "Unmute" else "Mute",
                            tint = DarkroomColours.PaperWhite,
                        )
                    }
                }
            }
        }
    }
}

private fun formatDuration(ms: Long): String {
    val totalSec = (ms / 1000L).coerceAtLeast(0L)
    val h = totalSec / 3600L
    val m = (totalSec % 3600L) / 60L
    val s = totalSec % 60L
    return if (h > 0L) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}

@Composable
private fun FilmstripRow(
    photos: List<PhotoWithCull>,
    currentIndex: Int,
    photoSource: PhotoSource,
    images: ImageRepository,
    onSelect: (Int) -> Unit,
) {
    LazyRow(
        modifier = Modifier
            .fillMaxWidth()
            .background(DarkroomColours.GraphiteSurface)
            .padding(horizontal = 8.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        itemsIndexed(photos, key = { _, p -> p.id }) { idx, p ->
            val thumb by produceState<Bitmap?>(initialValue = null, key1 = p.id) {
                value = images.loadThumbnail(photoSource, p, maxPx = 180)
            }
            val active = idx == currentIndex
            Box(
                modifier = Modifier
                    .size(56.dp)
                    .clip(RoundedCornerShape(6.dp))
                    .background(DarkroomColours.GraphiteRaised)
                    .border(if (active) 2.dp else 0.dp, if (active) DarkroomColours.SafelightAmber else Color.Transparent, RoundedCornerShape(6.dp))
                    .clickable { onSelect(idx) },
            ) {
                if (thumb != null) {
                    Image(
                        bitmap = thumb!!.asImageBitmap(),
                        contentDescription = p.relPath,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
            }
        }
    }
}

@Composable
private fun ViewerRatingBar(
    photo: PhotoWithCull,
    translucent: Boolean = false,
    onRate: (Int) -> Unit,
    onPick: () -> Unit,
    onReject: () -> Unit,
) {
    Surface(
        color = if (translucent) DarkroomColours.GraphiteSurface.copy(alpha = 0.78f) else DarkroomColours.GraphiteSurface,
    ) {
        Column(modifier = Modifier.navigationBarsPadding()) {
            HorizontalDivider(color = DarkroomColours.Hairline)
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = if (translucent) 2.dp else 8.dp),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                val isPick = photo.effectiveFlag == Flag.PICK.dbValue
                val isReject = photo.effectiveFlag == Flag.REJECT.dbValue

                IconButton(onClick = onPick, modifier = Modifier.size(48.dp)) {
                    Icon(
                        Icons.Default.Flag,
                        contentDescription = "Pick",
                        tint = if (isPick) DarkroomColours.SafelightAmber else DarkroomColours.AshMuted,
                    )
                }
                Row {
                    for (s in 1..5) {
                        val filled = s <= photo.effectiveStars
                        IconButton(onClick = { onRate(s) }, modifier = Modifier.size(44.dp)) {
                            Icon(
                                if (filled) Icons.Default.Star else Icons.Default.StarBorder,
                                contentDescription = "$s stars",
                                tint = if (filled) DarkroomColours.SafelightAmber else DarkroomColours.AshMuted,
                            )
                        }
                    }
                }
                IconButton(onClick = onReject, modifier = Modifier.size(48.dp)) {
                    Icon(
                        Icons.Default.Close,
                        contentDescription = "Reject",
                        tint = if (isReject) DarkroomColours.WarningRed else DarkroomColours.AshMuted,
                    )
                }
            }
        }
    }
}

@Composable
private fun PhotoDetailsContent(photo: PhotoWithCull, details: PhotoDetails?) {
    Column(
        modifier = Modifier.verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(photo.relPath, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DarkroomColours.PaperWhite)
        if (details?.histogram != null) {
            HistogramCard(details.histogram)
        }
        DetailRow("Camera", details?.camera)
        DetailRow("Lens", details?.lens)
        DetailRow("Exposure", details?.exposure)
        DetailRow("Focal length", details?.focalLength)
        DetailRow("Shot", details?.date)
        DetailRow("Dimensions", details?.dimensions)
        DetailRow("Size", details?.fileSize)
        if (photo.companionNames.isNotEmpty()) {
            DetailRow("Paired", photo.companionNames.replace('\n', ' '))
        }
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun DetailRow(label: String, value: String?) {
    if (value.isNullOrBlank()) return
    Column {
        Text(label, fontSize = 11.sp, color = DarkroomColours.AshMuted)
        Text(value, fontSize = 13.sp, color = DarkroomColours.PaperWhite)
    }
}

@Composable
private fun HistogramCard(h: Histogram) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(DarkroomColours.InkBlack)
            .border(1.dp, DarkroomColours.Hairline, RoundedCornerShape(8.dp))
            .padding(8.dp),
    ) {
        Canvas(modifier = Modifier.fillMaxWidth().height(72.dp)) {
            val bins = Histogram.BINS
            val peak = h.peak.toFloat().coerceAtLeast(1f)
            fun drawChannel(counts: IntArray, color: Color) {
                val path = Path()
                path.moveTo(0f, size.height)
                for (i in 0 until bins) {
                    val x = (i.toFloat() / (bins - 1)) * size.width
                    val y = size.height - (counts[i].toFloat() / peak).coerceIn(0f, 1f) * size.height
                    path.lineTo(x, y)
                }
                path.lineTo(size.width, size.height)
                path.close()
                drawPath(path, color = color.copy(alpha = 0.4f))
            }
            drawChannel(h.red, Color(0xFFFF5555))
            drawChannel(h.green, Color(0xFF55DD77))
            drawChannel(h.blue, Color(0xFF5599FF))
        }
        if (h.highlights >= Histogram.CLIP_SHOWN || h.shadows >= Histogram.CLIP_SHOWN) {
            Spacer(Modifier.height(4.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("Shadows ${Histogram.percent(h.shadows)}", fontSize = 11.sp, color = DarkroomColours.AshMuted)
                Text("Highlights ${Histogram.percent(h.highlights)}", fontSize = 11.sp, color = DarkroomColours.AshMuted)
            }
        }
    }
}
