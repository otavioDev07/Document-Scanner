package br.com.dinheironanota.document_scanner_flutter

internal data class StabilityUpdate(
    val state: String,
    val progress: Double,
    val stableFrames: Long,
    val shouldCapture: Boolean,
    val corners: DoubleArray? = null,
)

/**
 * Time-based stability tracker matching the legacy AutoScanHandler contract.
 *
 * A candidate must stay within [distanceThreshold] for [delayMs] and then for
 * [durationMs]. Movement is measured in oriented analysis-image pixels.
 */
internal class StabilityTracker(options: Map<String, Any?>?) {
    private var distanceThreshold = options.number("autoCaptureDistanceThreshold", 50.0)
    private var delayMs = options.number("autoCaptureDelayMs", 1000.0).toLong().coerceAtLeast(0)
    private var durationMs = options.number("autoCaptureDurationMs", 1000.0).toLong().coerceAtLeast(1)
    private var cooldownMs = options.number("autoCaptureCooldownMs", 1500.0).toLong().coerceAtLeast(0)

    private var previous: DoubleArray? = null
    private var displayed: DoubleArray? = null
    private var pendingMovement: DoubleArray? = null
    private var stableSinceNs = 0L
    private var stableFrames = 0L
    private var cooldownUntilNs = 0L
    private var capturedCurrentDocument = false

    @Synchronized
    fun updateOptions(options: Map<String, Any?>?) {
        distanceThreshold = options.number("autoCaptureDistanceThreshold", distanceThreshold)
        delayMs = options.number("autoCaptureDelayMs", delayMs.toDouble()).toLong().coerceAtLeast(0)
        durationMs = options.number("autoCaptureDurationMs", durationMs.toDouble()).toLong().coerceAtLeast(1)
        cooldownMs = options.number("autoCaptureCooldownMs", cooldownMs.toDouble()).toLong().coerceAtLeast(0)
    }

    @Synchronized
    fun update(
        corners: DoubleArray?,
        imageWidth: Int,
        imageHeight: Int,
        timestampNs: Long,
        autoCaptureEnabled: Boolean,
    ): StabilityUpdate {
        if (corners == null || corners.size != 8) {
            val hadDocument = previous != null
            resetCandidate()
            capturedCurrentDocument = false
            return StabilityUpdate(if (hadDocument) "lost" else "searching", 0.0, 0, false)
        }

        val prior = previous
        if (prior == null) {
            previous = corners.copyOf()
            displayed = corners.copyOf()
            stableSinceNs = timestampNs
            stableFrames = 1
            return StabilityUpdate(
                state = "detected",
                progress = 0.0,
                stableFrames = stableFrames,
                shouldCapture = false,
                corners = displayed?.copyOf(),
            )
        }

        if (maximumMovement(prior, corners, imageWidth, imageHeight) >= distanceThreshold) {
            val pending = pendingMovement
            if (
                pending != null &&
                maximumMovement(pending, corners, imageWidth, imageHeight) < distanceThreshold
            ) {
                // Match iOS: two consecutive, mutually close frames represent
                // real movement. A single distant contour is detector noise and
                // must not reset the progress.
                previous = corners.copyOf()
                displayed = smoothed(displayed, corners)
                pendingMovement = null
                stableSinceNs = timestampNs
                stableFrames = 1
                capturedCurrentDocument = false
                return StabilityUpdate(
                    state = "detected",
                    progress = 0.0,
                    stableFrames = stableFrames,
                    shouldCapture = false,
                    corners = displayed?.copyOf(),
                )
            }
            pendingMovement = corners.copyOf()
            return progressUpdate(
                timestampNs = timestampNs,
                autoCaptureEnabled = autoCaptureEnabled,
                allowCapture = false,
            )
        }

        pendingMovement = null
        previous = corners.copyOf()
        displayed = smoothed(displayed, corners)
        stableFrames += 1
        return progressUpdate(
            timestampNs = timestampNs,
            autoCaptureEnabled = autoCaptureEnabled,
            allowCapture = true,
        )
    }

    private fun progressUpdate(
        timestampNs: Long,
        autoCaptureEnabled: Boolean,
        allowCapture: Boolean,
    ): StabilityUpdate {
        val elapsedMs = (timestampNs - stableSinceNs).coerceAtLeast(0) / 1_000_000.0
        if (elapsedMs < delayMs) {
            return StabilityUpdate(
                state = "detected",
                progress = 0.0,
                stableFrames = stableFrames,
                shouldCapture = false,
                corners = displayed?.copyOf() ?: previous?.copyOf(),
            )
        }

        val scanningElapsedMs = elapsedMs - delayMs
        val progress = (scanningElapsedMs / durationMs).coerceIn(0.0, 1.0)
        if (scanningElapsedMs < durationMs) {
            return StabilityUpdate(
                state = "stabilizing",
                progress = progress,
                stableFrames = stableFrames,
                shouldCapture = false,
                corners = displayed?.copyOf() ?: previous?.copyOf(),
            )
        }

        val shouldCapture = allowCapture &&
            autoCaptureEnabled &&
            !capturedCurrentDocument &&
            timestampNs >= cooldownUntilNs
        if (shouldCapture) capturedCurrentDocument = true
        return StabilityUpdate(
            state = "stable",
            progress = 1.0,
            stableFrames = stableFrames,
            shouldCapture = shouldCapture,
            corners = displayed?.copyOf() ?: previous?.copyOf(),
        )
    }

    @Synchronized
    fun onCaptured(timestampNs: Long) {
        cooldownUntilNs = timestampNs + cooldownMs * 1_000_000L
        capturedCurrentDocument = true
    }

    @Synchronized
    fun reset() {
        resetCandidate()
        capturedCurrentDocument = false
        cooldownUntilNs = 0
    }

    private fun resetCandidate() {
        previous = null
        displayed = null
        pendingMovement = null
        stableSinceNs = 0
        stableFrames = 0
    }

    private fun smoothed(current: DoubleArray?, target: DoubleArray): DoubleArray {
        if (current == null || current.size != target.size) return target.copyOf()
        val factor = 0.35
        return DoubleArray(target.size) { index ->
            current[index] + (target[index] - current[index]) * factor
        }
    }

    private fun maximumMovement(
        first: DoubleArray,
        second: DoubleArray,
        width: Int,
        height: Int,
    ): Double =
        // Preserve the legacy iOS matching rule: track one inward-facing
        // axis per ordered corner so edge jitter does not look like movement.
        maxOf(
            kotlin.math.abs(first[0] - second[0]) * width,
            kotlin.math.abs(first[3] - second[3]) * height,
            kotlin.math.abs(first[4] - second[4]) * width,
            kotlin.math.abs(first[7] - second[7]) * height,
        )

    private fun Map<String, Any?>?.number(name: String, fallback: Double): Double =
        (this?.get(name) as? Number)?.toDouble() ?: fallback
}
