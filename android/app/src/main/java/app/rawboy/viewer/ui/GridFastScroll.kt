package app.rawboy.viewer.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

/** Fraction (0..1) of the way through the list for the first visible item. */
internal fun fastScrollFraction(firstVisibleIndex: Int, totalItems: Int, visibleItems: Int): Float {
    val scrollable = totalItems - visibleItems
    if (scrollable <= 0) return 0f
    return (firstVisibleIndex.toFloat() / scrollable).coerceIn(0f, 1f)
}

/** Item index to scroll to for a thumb at [fraction] (0..1). */
internal fun fastScrollTargetIndex(fraction: Float, totalItems: Int, visibleItems: Int): Int {
    val scrollable = totalItems - visibleItems
    if (scrollable <= 0) return 0
    return Math.round(fraction.coerceIn(0f, 1f) * scrollable).coerceIn(0, totalItems - 1)
}

/** Whether the list is long enough to need a thumb: more than ~3 screens of items. */
internal fun fastScrollNeeded(totalItems: Int, visibleItems: Int): Boolean =
    visibleItems > 0 && totalItems > visibleItems * 3

private const val IDLE_HIDE_MS = 1200L

/**
 * A draggable thumb along the right edge of a photo grid. Shows while the grid scrolls or the
 * thumb is dragged, fades out after [IDLE_HIDE_MS] idle, and only exists for long lists.
 */
@Composable
fun GridFastScroll(state: LazyGridState, modifier: Modifier = Modifier) {
    val needed by remember(state) {
        derivedStateOf {
            val info = state.layoutInfo
            fastScrollNeeded(info.totalItemsCount, info.visibleItemsInfo.size)
        }
    }
    if (!needed) return

    var dragging by remember { mutableStateOf(false) }
    var dragFraction by remember { mutableStateOf(0f) }
    var active by remember { mutableStateOf(false) }

    val scrolling = state.isScrollInProgress
    LaunchedEffect(scrolling, dragging) {
        if (scrolling || dragging) {
            active = true
        } else {
            delay(IDLE_HIDE_MS)
            active = false
        }
    }
    val alpha by animateFloatAsState(
        targetValue = if (active) 1f else 0f,
        animationSpec = tween(if (active) 120 else 400),
        label = "fastScrollAlpha",
    )

    val thumbHeight = 56.dp
    BoxWithConstraints(modifier = modifier.fillMaxHeight().width(28.dp)) {
        val density = LocalDensity.current
        val trackPx = with(density) { maxHeight.toPx() }
        val thumbPx = with(density) { thumbHeight.toPx() }
        val travel = (trackPx - thumbPx).coerceAtLeast(1f)

        val fraction = if (dragging) {
            dragFraction
        } else {
            val info = state.layoutInfo
            fastScrollFraction(state.firstVisibleItemIndex, info.totalItemsCount, info.visibleItemsInfo.size)
        }

        // Only grab touches while visible, so the grid underneath stays fully tappable.
        val touch = if (active) {
            Modifier.pointerInput(state) {
                detectVerticalDragGestures(
                    onDragStart = { offset ->
                        dragging = true
                        dragFraction = ((offset.y - thumbPx / 2) / travel).coerceIn(0f, 1f)
                    },
                    onDragEnd = { dragging = false },
                    onDragCancel = { dragging = false },
                ) { change, delta ->
                    change.consume()
                    dragFraction = (dragFraction + delta / travel).coerceIn(0f, 1f)
                }
            }
        } else {
            Modifier
        }

        LaunchedEffect(dragging) {
            if (!dragging) return@LaunchedEffect
            snapshotFlowDrag(state) { dragFraction }
        }

        Box(modifier = Modifier.fillMaxHeight().width(28.dp).then(touch)) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .offset { IntOffset(0, (fraction * travel).toInt()) }
                    .graphicsLayer { this.alpha = alpha }
                    .size(width = if (dragging) 10.dp else 6.dp, height = thumbHeight)
                    .background(
                        if (dragging) DarkroomColours.SafelightAmber else DarkroomColours.AshMuted,
                        RoundedCornerShape(3.dp),
                    ),
            )
        }
    }
}

private suspend fun snapshotFlowDrag(state: LazyGridState, fraction: () -> Float) {
    androidx.compose.runtime.snapshotFlow(fraction).collect { f ->
        val info = state.layoutInfo
        state.scrollToItem(fastScrollTargetIndex(f, info.totalItemsCount, info.visibleItemsInfo.size))
    }
}
