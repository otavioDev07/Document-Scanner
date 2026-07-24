package br.com.dinheironanota.document_scanner_flutter

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

internal class CameraPreviewTransformTest {
    @Test
    fun portraitSurfaceTextureUsesOrientedDimensionsWithoutDoubleTransform() {
        val transform = cameraXSurfaceTexturePreviewTransform(
            width = 1920,
            height = 1080,
            rotationDegrees = 90,
        )

        assertEquals(1080, transform.width)
        assertEquals(1920, transform.height)
        assertEquals(0, transform.rotationDegrees)
        assertFalse(transform.mirrored)
    }

    @Test
    fun landscapeSurfaceTextureKeepsItsDimensions() {
        val transform = cameraXSurfaceTexturePreviewTransform(
            width = 1920,
            height = 1080,
            rotationDegrees = 0,
        )

        assertEquals(1920, transform.width)
        assertEquals(1080, transform.height)
        assertEquals(0, transform.rotationDegrees)
        assertFalse(transform.mirrored)
    }
}
