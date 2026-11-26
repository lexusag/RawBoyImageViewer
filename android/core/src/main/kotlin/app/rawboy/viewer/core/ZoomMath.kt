package app.rawboy.viewer.core

import kotlin.math.abs

data class Point2D(val x: Double, val y: Double) {
    companion object {
        val ZERO = Point2D(0.0, 0.0)
    }
}

data class Size2D(val width: Double, val height: Double) {
    companion object {
        val ZERO = Size2D(0.0, 0.0)
    }
}

data class ZoomState(val scale: Double, val offset: Point2D = Point2D.ZERO)

data class SharedZoom(val factor: Double, val centre: Point2D = Point2D.ZERO) {
    companion object {
        val FIT = SharedZoom(factor = 1.0)
    }
}

/**
 * Fit, 1:1, zooming at a point and panning limits for one image in one view.
 * A port of RawBoyBrowseKit's `ZoomMath.swift`: keep the two in step.
 */
data class ZoomMath(
    val imageSize: Size2D,
    val viewSize: Size2D,
    val backingScale: Double,
) {
    private val safeBacking = maxOf(backingScale, 1.0)

    val oneToOneScale: Double get() = 1.0 / safeBacking

    val fitScale: Double
        get() {
            if (imageSize.width <= 0 || imageSize.height <= 0 || viewSize.width <= 0 || viewSize.height <= 0) {
                return oneToOneScale
            }
            return minOf(viewSize.width / imageSize.width, viewSize.height / imageSize.height, oneToOneScale)
        }

    val minScale: Double get() = fitScale
    val maxScale: Double get() = maxOf(oneToOneScale * MAX_ZOOM, fitScale)
    val fit: ZoomState get() = ZoomState(scale = fitScale)

    fun isFit(state: ZoomState): Boolean = abs(state.scale - fitScale) < fitScale * 1e-6

    fun devicePixelsPerImagePixel(state: ZoomState): Double = state.scale * safeBacking

    fun clamped(state: ZoomState): ZoomState {
        val scale = state.scale.coerceIn(minScale, maxScale)
        fun axis(offset: Double, image: Double, view: Double): Double {
            val slack = (image * scale - view) / 2.0
            return if (slack <= 0.0) 0.0 else offset.coerceIn(-slack, slack)
        }
        return ZoomState(
            scale = scale,
            offset = Point2D(
                x = axis(state.offset.x, imageSize.width, viewSize.width),
                y = axis(state.offset.y, imageSize.height, viewSize.height),
            ),
        )
    }

    fun zoomed(state: ZoomState, to: Double, around: Point2D): ZoomState {
        val target = to.coerceIn(minScale, maxScale)
        val ratio = target / state.scale
        val offset = Point2D(
            x = around.x - (around.x - state.offset.x) * ratio,
            y = around.y - (around.y - state.offset.y) * ratio,
        )
        return clamped(ZoomState(scale = target, offset = offset))
    }

    fun panned(state: ZoomState, by: Point2D): ZoomState =
        clamped(ZoomState(scale = state.scale, offset = Point2D(state.offset.x + by.x, state.offset.y + by.y)))

    fun toggled(state: ZoomState, around: Point2D): ZoomState =
        if (isFit(state)) zoomed(state, to = oneToOneScale, around = around) else fit

    companion object {
        const val MAX_ZOOM = 8.0
    }
}
