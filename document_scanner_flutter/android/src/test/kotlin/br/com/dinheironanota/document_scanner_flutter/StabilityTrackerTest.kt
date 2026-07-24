package br.com.dinheironanota.document_scanner_flutter

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class StabilityTrackerTest {
    private val corners = doubleArrayOf(0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9)

    @Test
    fun stableDocumentTriggersOnceAfterDelayAndDuration() {
        val tracker = StabilityTracker(
            mapOf(
                "autoCaptureDelayMs" to 100,
                "autoCaptureDurationMs" to 100,
                "autoCaptureCooldownMs" to 500,
            ),
        )
        val start = 1_000_000_000L
        assertEquals("detected", tracker.update(corners, 1000, 800, start, true).state)
        val waiting = tracker.update(corners, 1000, 800, start + 50_000_000L, true)
        assertEquals("detected", waiting.state)
        assertEquals(0.0, waiting.progress)
        val stabilizing = tracker.update(corners, 1000, 800, start + 150_000_000L, true)
        assertEquals("stabilizing", stabilizing.state)
        assertEquals(0.5, stabilizing.progress)
        val stable = tracker.update(corners, 1000, 800, start + 210_000_000L, true)
        assertEquals("stable", stable.state)
        assertTrue(stable.shouldCapture)
        assertFalse(
            tracker.update(corners, 1000, 800, start + 220_000_000L, true).shouldCapture,
        )
    }

    @Test
    fun isolatedContourJumpDoesNotResetProgressOrTriggerCapture() {
        val tracker = StabilityTracker(
            mapOf(
                "autoCaptureDistanceThreshold" to 10,
                "autoCaptureDelayMs" to 0,
                "autoCaptureDurationMs" to 100,
            ),
        )
        val start = 1_000_000_000L
        tracker.update(corners, 1000, 800, start, false)
        val moved = corners.copyOf().also { it[0] += 0.1 }
        val noisy = tracker.update(moved, 1000, 800, start + 110_000_000L, true)
        assertEquals("stable", noisy.state)
        assertEquals(1.0, noisy.progress)
        assertFalse(noisy.shouldCapture)
        assertContentEquals(corners, noisy.corners)

        val recovered = tracker.update(corners, 1000, 800, start + 120_000_000L, true)
        assertEquals("stable", recovered.state)
        assertTrue(recovered.shouldCapture)
    }

    @Test
    fun twoConsecutiveMovedContoursResetTheCandidate() {
        val tracker = StabilityTracker(mapOf("autoCaptureDistanceThreshold" to 10))
        val start = 1_000_000_000L
        tracker.update(corners, 1000, 800, start, false)
        val moved = corners.copyOf().also { it[0] += 0.1 }
        tracker.update(moved, 1000, 800, start + 10_000_000L, false)
        val movedAgain = moved.copyOf().also { it[0] += 0.001 }
        assertEquals(
            "detected",
            tracker.update(movedAgain, 1000, 800, start + 20_000_000L, false).state,
        )
    }

    @Test
    fun movementAndLossResetTheCandidate() {
        val tracker = StabilityTracker(null)
        val start = 1_000_000_000L
        tracker.update(corners, 1000, 800, start, false)
        assertEquals(
            "lost",
            tracker.update(null, 1000, 800, start + 20_000_000L, false).state,
        )
        assertEquals(
            "searching",
            tracker.update(null, 1000, 800, start + 30_000_000L, false).state,
        )
    }

    @Test
    fun displayedCornersUseTheSameSmoothingAsIos() {
        val tracker = StabilityTracker(mapOf("autoCaptureDistanceThreshold" to 200))
        val start = 1_000_000_000L
        tracker.update(corners, 1000, 800, start, false)
        val shifted = corners.copyOf().also { it[0] += 0.1 }

        val update = tracker.update(shifted, 1000, 800, start + 10_000_000L, false)

        assertEquals(0.135, update.corners!![0], absoluteTolerance = 0.000001)
    }

    @Test
    fun edgeAxisJitterUsesTheSameMovementRuleAsIos() {
        val tracker = StabilityTracker(mapOf("autoCaptureDistanceThreshold" to 10))
        val start = 1_000_000_000L
        tracker.update(corners, 1000, 800, start, false)
        val edgeJitter = corners.copyOf().also { it[1] += 0.1 }

        val update = tracker.update(edgeJitter, 1000, 800, start + 10_000_000L, false)

        assertEquals(2, update.stableFrames)
    }
}
