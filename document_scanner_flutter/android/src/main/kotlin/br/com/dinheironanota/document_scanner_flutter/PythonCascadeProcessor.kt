package br.com.dinheironanota.document_scanner_flutter

import android.content.Context
import android.graphics.Bitmap
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

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

/** Long-lived Chaquopy bridge. A Python interpreter/module is never recreated per frame. */
internal class PythonCascadeProcessor(context: Context) {
    private val module = synchronized(PythonCascadeProcessor::class.java) {
        if (!Python.isStarted()) Python.start(AndroidPlatform(context.applicationContext))
        Python.getInstance().getModule("coupon_pipeline")
    }

    fun processFrame(
        yBuffer: ByteBuffer,
        uBuffer: ByteBuffer,
        vBuffer: ByteBuffer,
        width: Int,
        height: Int,
        yRowStride: Int,
        uRowStride: Int,
        vRowStride: Int,
        chromaPixelStride: Int,
        rotationDegrees: Int,
        rdpCorners: DoubleArray?,
        rdpScore: Double,
    ): CascadeDetection {
        val compactNv21 = compactYuv420(
            yBuffer = yBuffer,
            uBuffer = uBuffer,
            vBuffer = vBuffer,
            width = width,
            height = height,
            yRowStride = yRowStride,
            uRowStride = uRowStride,
            vRowStride = vRowStride,
            chromaPixelStride = chromaPixelStride,
        )
        val json = module.callAttr(
            "process_frame",
            compactNv21,
            width,
            height,
            rotationDegrees,
            rdpCorners,
            rdpScore,
        ).toString()
        return parse(json)
    }

    /**
     * Runs the static-image cascade over the same EXIF-oriented bitmap used by
     * C++ detection and perspective crop. Reading the original file in Python
     * would ignore EXIF rotation and put the candidate points in another space.
     */
    fun encodeBitmap(bitmap: Bitmap): ByteArray = ByteArrayOutputStream().use { stream ->
        check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
            "Unable to encode the oriented bitmap for the detection pipeline"
        }
        stream.toByteArray()
    }

    fun processEncodedBitmap(
        encodedBitmap: ByteArray,
        rdpCorners: DoubleArray?,
        rdpScore: Double,
    ): CascadeDetection = parse(
            module.callAttr("process_encoded_image", encodedBitmap, rdpCorners, rdpScore).toString(),
        )

    /** Evaluates sharpness of an already warped crop without running detectors. */
    fun evaluateCrop(bitmap: Bitmap): FftValidation {
        // FFT cost grows with every pixel. This image is a quality probe, not
        // the delivered crop, so cap only the probe while preserving the full
        // resolution bitmap for the final native crop.
        val largest = maxOf(bitmap.width, bitmap.height)
        val fftBitmap = if (largest <= FFT_MAX_DIMENSION) {
            bitmap
        } else {
            val scale = FFT_MAX_DIMENSION.toDouble() / largest
            Bitmap.createScaledBitmap(
                bitmap,
                (bitmap.width * scale).toInt().coerceAtLeast(1),
                (bitmap.height * scale).toInt().coerceAtLeast(1),
                true,
            )
        }
        val value = try {
            JSONObject(
                module.callAttr("evaluate_encoded_crop", encodeBitmap(fftBitmap)).toString(),
            )
        } finally {
            if (fftBitmap !== bitmap) fftBitmap.recycle()
        }
        value.optString("error").takeIf { it.isNotBlank() }?.let { error ->
            throw CameraOperationException("PYTHON_PIPELINE_FAILED", error)
        }
        return FftValidation(
            valid = value.optBoolean("valid", false),
            score = value.optDouble("fftScore", 0.0),
        )
    }

    private fun parse(raw: String): CascadeDetection {
        val value = JSONObject(raw)
        val pipelineError = value.optString("error").takeIf { it.isNotBlank() }
        if (pipelineError != null) {
            throw CameraOperationException("PYTHON_PIPELINE_FAILED", pipelineError)
        }
        val valid = value.optBoolean("valid", false)
        val rawPoints = value.optJSONArray("points")
        val corners = if (valid && rawPoints != null && rawPoints.length() == 4) {
            DoubleArray(8) { coordinate ->
                val point = rawPoints.getJSONArray(coordinate / 2)
                point.getDouble(coordinate % 2)
            }
        } else {
            null
        }
        return CascadeDetection(
            corners = corners,
            confidence = value.optDouble("score", 0.0),
            source = value.optString("engine", "cascade"),
            fftScore = if (value.isNull("fftScore")) null else value.optDouble("fftScore"),
        )
    }

    private fun compactYuv420(
        yBuffer: ByteBuffer,
        uBuffer: ByteBuffer,
        vBuffer: ByteBuffer,
        width: Int,
        height: Int,
        yRowStride: Int,
        uRowStride: Int,
        vRowStride: Int,
        chromaPixelStride: Int,
    ): ByteArray {
        require(width > 0 && height > 0 && width % 2 == 0 && height % 2 == 0) {
            "YUV_420_888 dimensions must be positive and even"
        }
        require(yRowStride >= width && chromaPixelStride > 0) { "Invalid YUV plane layout" }
        val yPlane = yBuffer.duplicate()
        val uPlane = uBuffer.duplicate()
        val vPlane = vBuffer.duplicate()
        val output = ByteArray(width * height * 3 / 2)
        for (row in 0 until height) {
            yPlane.position(row * yRowStride)
            yPlane.get(output, row * width, width)
        }
        var outputIndex = width * height
        for (row in 0 until height / 2) {
            for (column in 0 until width / 2) {
                val chromaOffset = column * chromaPixelStride
                output[outputIndex++] = vPlane.get(row * vRowStride + chromaOffset)
                output[outputIndex++] = uPlane.get(row * uRowStride + chromaOffset)
            }
        }
        return output
    }

    private companion object {
        const val FFT_MAX_DIMENSION = 1280
    }
}
