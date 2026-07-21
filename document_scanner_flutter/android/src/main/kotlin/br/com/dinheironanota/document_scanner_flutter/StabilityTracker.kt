package br.com.dinheironanota.document_scanner_flutter

import kotlin.math.hypot

internal data class StabilityUpdate(
    val state: String,
    val progress: Double,
    val stableFrames: Long,
    val shouldCapture: Boolean,
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
            stableSinceNs = timestampNs
            stableFrames = 1
            return StabilityUpdate("detected", 0.0, stableFrames, false)
        }

        val maximumMovement = maximumCornerDistance(prior, corners, imageWidth, imageHeight)
        previous = corners.copyOf()
        if (maximumMovement >= distanceThreshold) {
            stableSinceNs = timestampNs
            stableFrames = 1
            capturedCurrentDocument = false
            return StabilityUpdate("detected", 0.0, stableFrames, false)
        }

        stableFrames += 1
        val elapsedMs = (timestampNs - stableSinceNs).coerceAtLeast(0) / 1_000_000.0
        val totalMs = delayMs + durationMs
        val progress = (elapsedMs / totalMs).coerceIn(0.0, 1.0)
        if (elapsedMs < totalMs) {
            return StabilityUpdate("stabilizing", progress, stableFrames, false)
        }

        val shouldCapture = autoCaptureEnabled &&
            !capturedCurrentDocument &&
            timestampNs >= cooldownUntilNs
        if (shouldCapture) capturedCurrentDocument = true
        return StabilityUpdate("stable", 1.0, stableFrames, shouldCapture)
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
        stableSinceNs = 0
        stableFrames = 0
    }

    private fun maximumCornerDistance(
        first: DoubleArray,
        second: DoubleArray,
        width: Int,
        height: Int,
    ): Double {
        var maximum = 0.0
        for (index in 0 until 4) {
            val dx = (first[index * 2] - second[index * 2]) * width
            val dy = (first[index * 2 + 1] - second[index * 2 + 1]) * height
            maximum = maxOf(maximum, hypot(dx, dy))
        }
        return maximum
    }

    private fun Map<String, Any?>?.number(name: String, fallback: Double): Double =
        (this?.get(name) as? Number)?.toDouble() ?: fallback
}
