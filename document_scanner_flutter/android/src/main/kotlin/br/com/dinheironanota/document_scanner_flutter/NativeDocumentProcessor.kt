package br.com.dinheironanota.document_scanner_flutter

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File
import java.io.FileNotFoundException
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt

internal class NativeDocumentProcessor {
    init {
        System.loadLibrary("document_scanner_flutter")
    }

    fun detect(sourcePath: String, options: Map<String, Any?>?): Map<String, Any?> {
        val bitmap = OrientedBitmapDecoder.decode(sourcePath)
        try {
            val resizeThreshold = options.number("detectionResizeThreshold", 1200.0)
                .roundToInt().coerceAtLeast(0)
            val areaScaleMinFactor = options.number("areaScaleMinFactor", 0.04)
                .coerceIn(0.0, 1.0)
            val raw = nativeDetect(bitmap, resizeThreshold, areaScaleMinFactor)
            val corners = raw?.let { points ->
                require(points.size == 8) { "Native detector returned an invalid point count" }
                List(4) { index ->
                    mapOf(
                        "x" to (points[index * 2] / bitmap.width).coerceIn(0.0, 1.0),
                        "y" to (points[index * 2 + 1] / bitmap.height).coerceIn(0.0, 1.0),
                    )
                }
            }
            return mapOf(
                "corners" to corners,
                "imageWidth" to bitmap.width,
                "imageHeight" to bitmap.height,
                "rotationDegrees" to 0,
                "mirrored" to false,
                "source" to "legacy_contour_detector",
                "confidence" to null,
            )
        } finally {
            bitmap.recycle()
        }
    }

    fun crop(
        sourcePath: String,
        corners: List<Map<String, Number>>,
        options: Map<String, Any?>?,
        outputDirectory: File,
    ): Map<String, Any> {
        require(corners.size == 4) { "Exactly four corners are required" }
        val values = DoubleArray(8)
        corners.forEachIndexed { index, point ->
            val x = point["x"]?.toDouble() ?: throw IllegalArgumentException("corner[$index].x is required")
            val y = point["y"]?.toDouble() ?: throw IllegalArgumentException("corner[$index].y is required")
            require(x in 0.0..1.0 && y in 0.0..1.0) { "Corner values must be normalized" }
            values[index * 2] = x
            values[index * 2 + 1] = y
        }

        val source = OrientedBitmapDecoder.decode(sourcePath)
        try {
            val tl = PixelPoint(values[0] * source.width, values[1] * source.height)
            val tr = PixelPoint(values[2] * source.width, values[3] * source.height)
            val br = PixelPoint(values[4] * source.width, values[5] * source.height)
            val bl = PixelPoint(values[6] * source.width, values[7] * source.height)
            var outputWidth = max(distance(tl, tr), distance(bl, br)).roundToInt().coerceAtLeast(1)
            var outputHeight = max(distance(tl, bl), distance(tr, br)).roundToInt().coerceAtLeast(1)

            val maxDimension = options.number("maxOutputDimension", 4096.0).roundToInt().coerceAtLeast(1)
            val largest = max(outputWidth, outputHeight)
            if (largest > maxDimension) {
                val scale = maxDimension.toDouble() / largest
                outputWidth = (outputWidth * scale).roundToInt().coerceAtLeast(1)
                outputHeight = (outputHeight * scale).roundToInt().coerceAtLeast(1)
            }

            val output = Bitmap.createBitmap(outputWidth, outputHeight, Bitmap.Config.ARGB_8888)
            try {
                nativeCrop(source, values, output)
                val directory = File(outputDirectory, "document_scanner_flutter/output")
                directory.mkdirs()
                val outputFile = File(directory, "crop_${System.currentTimeMillis()}.jpg")
                val quality = options.number("jpegQuality", 92.0).roundToInt().coerceIn(1, 100)
                outputFile.outputStream().use { stream ->
                    check(output.compress(Bitmap.CompressFormat.JPEG, quality, stream)) {
                        "Unable to encode cropped image"
                    }
                }
                return mapOf(
                    "path" to outputFile.absolutePath,
                    "width" to outputWidth,
                    "height" to outputHeight,
                )
            } finally {
                output.recycle()
            }
        } finally {
            source.recycle()
        }
    }

    private external fun nativeDetect(
        sourceBitmap: Bitmap,
        resizeThreshold: Int,
        areaScaleMinFactor: Double,
    ): DoubleArray?

    private external fun nativeCrop(
        sourceBitmap: Bitmap,
        normalizedPoints: DoubleArray,
        outputBitmap: Bitmap,
    )

    private data class PixelPoint(val x: Double, val y: Double)

    private fun distance(first: PixelPoint, second: PixelPoint): Double =
        hypot(first.x - second.x, first.y - second.y)

    private fun Map<String, Any?>?.number(name: String, fallback: Double): Double =
        (this?.get(name) as? Number)?.toDouble() ?: fallback
}

internal object OrientedBitmapDecoder {
    fun decode(path: String): Bitmap {
        val file = File(path)
        if (!file.isFile) throw FileNotFoundException("Image does not exist: $path")
        val bitmap = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }) ?: throw IllegalArgumentException("Unable to decode image: $path")
        return ExifOrientation.apply(file, bitmap)
    }
}
