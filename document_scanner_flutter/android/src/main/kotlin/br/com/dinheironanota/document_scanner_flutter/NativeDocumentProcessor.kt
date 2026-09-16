package br.com.dinheironanota.document_scanner_flutter

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File
import java.io.FileNotFoundException
import java.nio.ByteBuffer
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt

internal data class CascadeDetection(
    val corners: DoubleArray?,
    val confidence: Double,
    val source: String,
    val fftScore: Double?,
)

internal data class FftValidation(
    val valid: Boolean,
    val score: Double,
)

internal class NativeDocumentProcessor(@Suppress("UNUSED_PARAMETER") context: Context) {
    init {
        System.loadLibrary("document_scanner_flutter")
    }

    fun detect(
        sourcePath: String,
        options: Map<String, Any?>?,
        previewCorners: List<Map<String, Number>>? = null,
    ): Map<String, Any?> {
        val bitmap = OrientedBitmapDecoder.decode(sourcePath)
        try {
            val resizeThreshold = options.number("detectionResizeThreshold", 1200.0)
                .roundToInt().coerceAtLeast(0)
            val areaScaleMinFactor = options.number("areaScaleMinFactor", 0.04)
                .coerceIn(0.0, 1.0)
            val hint = previewCorners?.toPixelCoordinates(bitmap.width, bitmap.height)
            val detection = if (hint != null) {
                // Performance-test path: trust the reduced-preview geometry,
                // scale it to the EXIF-oriented photo, warp once and run FFT
                // on that crop only. There is intentionally no full-res search.
                validatePreviewCrop(
                    source = bitmap,
                    previewPoints = hint,
                    maxOutputDimension = options.number("maxOutputDimension", 4096.0)
                        .roundToInt().coerceAtLeast(1),
                )
            } else {
                val raw = nativeDetect(bitmap, resizeThreshold, areaScaleMinFactor)
                decodeCascade(
                    nativeProcessBitmapCascade(
                        bitmap,
                        raw,
                        geometryScore(raw, bitmap.width, bitmap.height),
                    ),
                )
            }
            // The native detector and cascade share this same EXIF-oriented bitmap.
            val corners = detection.corners?.let { points ->
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
                "source" to detection.source,
                "confidence" to detection.confidence,
                "fftScore" to detection.fftScore,
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
            val maxDimension = options.number("maxOutputDimension", 4096.0).roundToInt().coerceAtLeast(1)
            val outputSize = cropSize(values, source.width, source.height, maxDimension)

            val output = Bitmap.createBitmap(outputSize.width, outputSize.height, Bitmap.Config.ARGB_8888)
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
                    "width" to outputSize.width,
                    "height" to outputSize.height,
                )
            } finally {
                output.recycle()
            }
        } finally {
            source.recycle()
        }
    }

    fun applyFilter(
        sourcePath: String,
        outputPath: String,
        filter: String,
        outputFormat: String,
        jpegQuality: Int,
    ): Map<String, Any> {
        require(filter in SUPPORTED_FILTERS) { "Unsupported filter: $filter" }
        val source = OrientedBitmapDecoder.decode(sourcePath)
        try {
            val output = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
            try {
                nativeApplyFilter(source, filter, output)
                val outputFile = File(outputPath)
                outputFile.parentFile?.mkdirs()
                val format = if (outputFormat == "png") {
                    Bitmap.CompressFormat.PNG
                } else {
                    Bitmap.CompressFormat.JPEG
                }
                outputFile.outputStream().use { stream ->
                    check(output.compress(format, jpegQuality.coerceIn(1, 100), stream)) {
                        "Unable to encode filtered image"
                    }
                }
                return mapOf(
                    "path" to outputFile.absolutePath,
                    "width" to output.width,
                    "height" to output.height,
                )
            } finally {
                output.recycle()
            }
        } finally {
            source.recycle()
        }
    }

    fun detectFrame(
        width: Int,
        height: Int,
        chromaPixelStride: Int,
        yBuffer: ByteBuffer,
        yRowStride: Int,
        uBuffer: ByteBuffer,
        uRowStride: Int,
        vBuffer: ByteBuffer,
        vRowStride: Int,
        rotationDegrees: Int,
        resizeThreshold: Int,
        areaScaleMinFactor: Double,
    ): CascadeDetection {
        // nativeDetectYuv returns normalized coordinates, while the native
        // cascade operates in pixels for geometry, warping and consensus.
        val normalizedRdpCorners = nativeDetectYuv(
            width,
            height,
            chromaPixelStride,
            yBuffer,
            yRowStride,
            uBuffer,
            uRowStride,
            vBuffer,
            vRowStride,
            rotationDegrees,
            resizeThreshold,
            areaScaleMinFactor,
        )
        val swapsDimensions = rotationDegrees == 90 || rotationDegrees == 270
        val orientedWidth = if (swapsDimensions) height else width
        val orientedHeight = if (swapsDimensions) width else height
        val rdpCorners = normalizedRdpCorners?.toPixelCoordinates(
            width = orientedWidth,
            height = orientedHeight,
        )
        val detection = decodeCascade(
            nativeProcessYuvCascade(
                width, height, chromaPixelStride, yBuffer, yRowStride, uBuffer, uRowStride,
                vBuffer, vRowStride, rotationDegrees, rdpCorners,
                geometryScore(rdpCorners, orientedWidth, orientedHeight),
            ),
        )
        // The controller and DocumentOverlay use normalized preview points;
        // native candidates are pixels, so normalize only at this UI boundary.
        return detection.copy(
            corners = detection.corners?.toNormalizedCoordinates(
                width = orientedWidth,
                height = orientedHeight,
            ),
        )
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

    private external fun nativeApplyFilter(
        sourceBitmap: Bitmap,
        filter: String,
        outputBitmap: Bitmap,
    )

    private external fun nativeDetectYuv(
        width: Int,
        height: Int,
        chromaPixelStride: Int,
        yBuffer: ByteBuffer,
        yRowStride: Int,
        uBuffer: ByteBuffer,
        uRowStride: Int,
        vBuffer: ByteBuffer,
        vRowStride: Int,
        rotationDegrees: Int,
        resizeThreshold: Int,
        areaScaleMinFactor: Double,
    ): DoubleArray?

    private external fun nativeProcessBitmapCascade(
        sourceBitmap: Bitmap,
        rdpCorners: DoubleArray?,
        rdpScore: Double,
    ): DoubleArray?

    private external fun nativeProcessYuvCascade(
        width: Int,
        height: Int,
        chromaPixelStride: Int,
        yBuffer: ByteBuffer,
        yRowStride: Int,
        uBuffer: ByteBuffer,
        uRowStride: Int,
        vBuffer: ByteBuffer,
        vRowStride: Int,
        rotationDegrees: Int,
        rdpCorners: DoubleArray?,
        rdpScore: Double,
    ): DoubleArray?

    private external fun nativeEvaluateSharpness(sourceBitmap: Bitmap): DoubleArray?

    private data class PixelPoint(val x: Double, val y: Double)

    private fun distance(first: PixelPoint, second: PixelPoint): Double =
        hypot(first.x - second.x, first.y - second.y)

    private data class CropSize(val width: Int, val height: Int)

    private fun cropSize(
        normalizedPoints: DoubleArray,
        sourceWidth: Int,
        sourceHeight: Int,
        maxOutputDimension: Int,
    ): CropSize {
        val tl = PixelPoint(normalizedPoints[0] * sourceWidth, normalizedPoints[1] * sourceHeight)
        val tr = PixelPoint(normalizedPoints[2] * sourceWidth, normalizedPoints[3] * sourceHeight)
        val br = PixelPoint(normalizedPoints[4] * sourceWidth, normalizedPoints[5] * sourceHeight)
        val bl = PixelPoint(normalizedPoints[6] * sourceWidth, normalizedPoints[7] * sourceHeight)
        var width = max(distance(tl, tr), distance(bl, br)).roundToInt().coerceAtLeast(1)
        var height = max(distance(tl, bl), distance(tr, br)).roundToInt().coerceAtLeast(1)
        val largest = max(width, height)
        if (largest > maxOutputDimension) {
            val scale = maxOutputDimension.toDouble() / largest
            width = (width * scale).roundToInt().coerceAtLeast(1)
            height = (height * scale).roundToInt().coerceAtLeast(1)
        }
        return CropSize(width, height)
    }

    private fun validatePreviewCrop(
        source: Bitmap,
        previewPoints: DoubleArray,
        maxOutputDimension: Int,
    ): CascadeDetection {
        val normalizedPoints = previewPoints.toNormalizedCoordinates(source.width, source.height)
        val outputSize = cropSize(normalizedPoints, source.width, source.height, maxOutputDimension)
        val warped = Bitmap.createBitmap(outputSize.width, outputSize.height, Bitmap.Config.ARGB_8888)
        return try {
            nativeCrop(source, normalizedPoints, warped)
            val fft = decodeSharpness(nativeEvaluateSharpness(warped))
            if (fft.valid) {
                CascadeDetection(
                    corners = previewPoints,
                    confidence = fft.score,
                    source = "preview_scaled",
                    fftScore = fft.score,
                )
            } else {
                CascadeDetection(
                    corners = null,
                    confidence = fft.score,
                    source = "fft_rejected",
                    fftScore = fft.score,
                )
            }
        } finally {
            warped.recycle()
        }
    }

    private fun DoubleArray.toPixelCoordinates(width: Int, height: Int): DoubleArray {
        require(size == 8) { "A document quadrilateral must contain four points" }
        return DoubleArray(size) { index ->
            val dimension = if (index % 2 == 0) width else height
            (this[index] * dimension).coerceIn(0.0, dimension.toDouble())
        }
    }

    /** Decodes the fixed native ABI without allocations for JSON, PNG or a JVM object graph per frame. */
    private fun decodeCascade(raw: DoubleArray?): CascadeDetection {
        require(raw != null && raw.size == CASCADE_RESULT_SIZE) { "Native cascade returned an invalid result" }
        val valid = raw[0] != 0.0
        val found = raw[1] != 0.0
        val corners = if (valid && found) DoubleArray(8) { raw[5 + it] } else null
        return CascadeDetection(
            corners = corners,
            confidence = raw[2],
            source = CASCADE_SOURCES[raw[4].toInt()] ?: "native_cascade",
            fftScore = raw[3].takeUnless { it.isNaN() },
        )
    }

    private fun decodeSharpness(raw: DoubleArray?): FftValidation {
        require(raw != null && raw.size == CASCADE_RESULT_SIZE) { "Native sharpness evaluator returned an invalid result" }
        return FftValidation(valid = raw[0] != 0.0, score = raw[3].takeUnless { it.isNaN() } ?: 0.0)
    }

    private fun List<Map<String, Number>>.toPixelCoordinates(
        width: Int,
        height: Int,
    ): DoubleArray? {
        if (size != 4 || width <= 0 || height <= 0) return null
        val result = DoubleArray(8)
        for (coordinate in result.indices) {
            val point = get(coordinate / 2)
            val value = point[if (coordinate % 2 == 0) "x" else "y"]?.toDouble()
                ?: return null
            val dimension = if (coordinate % 2 == 0) width else height
            result[coordinate] = (value * dimension).coerceIn(0.0, dimension.toDouble())
        }
        return result
    }

    private fun DoubleArray.toNormalizedCoordinates(width: Int, height: Int): DoubleArray {
        require(size == 8) { "A document quadrilateral must contain four points" }
        require(width > 0 && height > 0) { "Preview dimensions must be positive" }
        return DoubleArray(size) { index ->
            val dimension = if (index % 2 == 0) width else height
            (this[index] / dimension).coerceIn(0.0, 1.0)
        }
    }

    /** Same normalized area × orthogonality score used by pipeline.sh. */
    private fun geometryScore(points: DoubleArray?, width: Int, height: Int): Double {
        if (points == null || points.size != 8 || width <= 0 || height <= 0) return 0.0
        var twiceArea = 0.0
        var maxCosine = 0.0
        for (index in 0 until 4) {
            val next = (index + 1) % 4
            twiceArea += points[index * 2] * points[next * 2 + 1] -
                points[next * 2] * points[index * 2 + 1]

            val previous = (index + 3) % 4
            val ax = points[previous * 2] - points[index * 2]
            val ay = points[previous * 2 + 1] - points[index * 2 + 1]
            val bx = points[next * 2] - points[index * 2]
            val by = points[next * 2 + 1] - points[index * 2 + 1]
            val divisor = hypot(ax, ay) * hypot(bx, by)
            if (divisor > 1e-5) {
                maxCosine = max(maxCosine, kotlin.math.abs((ax * bx + ay * by) / divisor))
            }
        }
        val relativeArea = kotlin.math.abs(twiceArea) / 2.0 / (width.toDouble() * height)
        return relativeArea * (1.0 - maxCosine)
    }

    private fun Map<String, Any?>?.number(name: String, fallback: Double): Double =
        (this?.get(name) as? Number)?.toDouble() ?: fallback

    private companion object {
        const val CASCADE_RESULT_SIZE = 13
        val CASCADE_SOURCES = mapOf(
            1 to "cpp_rdp_hough",
            2 to "native_hough",
            3 to "native_watershed",
            4 to "native_watershed_area_guard",
            5 to "fft_rejected",
            6 to "underexposed_preview",
            7 to "arbiter",
            8 to "arbiter_fallback_lock",
            9 to "consensus_native",
        )
        val SUPPORTED_FILTERS = setOf("original", "grayscale", "highContrast", "colorBoost")
    }
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
