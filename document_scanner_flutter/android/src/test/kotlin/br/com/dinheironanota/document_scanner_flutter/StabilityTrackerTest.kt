package br.com.dinheironanota.document_scanner_flutter

import kotlin.test.Test
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
        assertEquals(
            "stabilizing",
            tracker.update(corners, 1000, 800, start + 150_000_000L, true).state,
        )
        val stable = tracker.update(corners, 1000, 800, start + 210_000_000L, true)
        assertEquals("stable", stable.state)
        assertTrue(stable.shouldCapture)
        assertFalse(
            tracker.update(corners, 1000, 800, start + 220_000_000L, true).shouldCapture,
        )
    }

    @Test
    fun movementAndLossResetTheCandidate() {
        val tracker = StabilityTracker(mapOf("autoCaptureDistanceThreshold" to 10))
        val start = 1_000_000_000L
        tracker.update(corners, 1000, 800, start, false)
        val moved = corners.copyOf().also { it[0] += 0.1 }
        assertEquals(
            "detected",
            tracker.update(moved, 1000, 800, start + 10_000_000L, false).state,
        )
        assertEquals(
            "lost",
            tracker.update(null, 1000, 800, start + 20_000_000L, false).state,
        )
        assertEquals(
            "searching",
            tracker.update(null, 1000, 800, start + 30_000_000L, false).state,
        )
    }
}
