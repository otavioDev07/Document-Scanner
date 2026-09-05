package br.com.dinheironanota.document_scanner_flutter

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.view.Surface
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.roundToLong

internal class CameraOperationException(
    val code: String,
    message: String,
    cause: Throwable? = null,
) : RuntimeException(message, cause)

/** Owns CameraX, the Flutter Texture, analysis backpressure, and capture. */
internal class CameraSession(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    private val processor: NativeDocumentProcessor,
    private val mainHandler: Handler,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private val mainExecutor = ContextCompat.getMainExecutor(context)
    private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val captureExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val capturing = AtomicBoolean(false)
    private val metrics = CameraMetrics()

    private var activity: Activity? = null
    private var provider: ProcessCameraProvider? = null
    private var preview: Preview? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var imageCapture: ImageCapture? = null
    private var camera: Camera? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var lensFacing = CameraSelector.LENS_FACING_BACK
    private var desiredPreview = false
    private var active = false
    private var disposed = false
    private var autoCaptureEnabled = false
    private var diagnosticsEnabled = false
    private var previewWidth = 0
    private var previewHeight = 0
    private var previewRotation = 0
    private var previewCropWidth = 0
    private var previewCropHeight = 0
    private var previewTransformationReady = false
    private var options: Map<String, Any?>? = null
    private var stabilityTracker = StabilityTracker(null)
    private var pendingStart: ((Result<Map<String, Any>>) -> Unit)? = null
    private var lastHadDocument = false
    private var latestDisplayedCorners: DoubleArray? = null
    private var blurWarningVisible = false
    private var previewAnnouncementPending = false

    fun start(
        activity: Activity,
        options: Map<String, Any?>?,
        callback: (Result<Map<String, Any>>) -> Unit,
    ) {
        if (disposed) {
            callback(Result.failure(CameraOperationException("DISPOSED", "Camera session is disposed")))
            return
        }
        if (pendingStart != null) {
            callback(Result.failure(CameraOperationException("BUSY", "Camera preview is already starting")))
            return
        }
        this.activity = activity
        this.options = options
        autoCaptureEnabled = options.boolean("autoCapture", false)
        diagnosticsEnabled = options.boolean("diagnosticsEnabled", false)
        stabilityTracker = StabilityTracker(options)
        desiredPreview = true
        pendingStart = callback
        ensureTexture()
        bindUseCases()
    }

    fun attachActivity(activity: Activity) {
        this.activity = activity
        if (desiredPreview && !active && pendingStart == null) {
            bindUseCases()
        }
    }

    fun detachActivity(preservePreviewIntent: Boolean) {
        activity = null
        unbindOwnedUseCases()
        active = false
        if (!preservePreviewIntent) {
            desiredPreview = false
            releaseTexture()
        }
    }

    fun pause() {
        checkUsable()
        unbindOwnedUseCases()
        active = false
        stabilityTracker.reset()
        emitCameraState("paused")
    }

    fun resume(callback: (Result<Map<String, Any>>) -> Unit) {
        checkUsable()
        val currentActivity = activity
            ?: throw CameraOperationException("NO_ACTIVITY", "Camera preview requires an attached Activity")
        start(currentActivity, options, callback)
    }

    fun switchCamera(callback: (Result<Map<String, Any>>) -> Unit) {
        checkActive()
        if (pendingStart != null) {
            callback(Result.failure(CameraOperationException("BUSY", "Camera is already reconfiguring")))
            return
        }
        lensFacing = if (lensFacing == CameraSelector.LENS_FACING_BACK) {
            CameraSelector.LENS_FACING_FRONT
        } else {
            CameraSelector.LENS_FACING_BACK
        }
        stabilityTracker.reset()
        lastHadDocument = false
        pendingStart = callback
        bindUseCases()
    }

    fun setAutoCapture(enabled: Boolean) {
        checkUsable()
        autoCaptureEnabled = enabled
        if (!enabled) stabilityTracker.reset()
    }

    fun setFlashMode(mode: String) {
        checkActive()
        val currentCapture = imageCapture
            ?: throw CameraOperationException("INVALID_STATE", "Image capture is not ready")
        when (mode) {
            "off" -> {
                camera?.cameraControl?.enableTorch(false)
                currentCapture.flashMode = ImageCapture.FLASH_MODE_OFF
            }
            "auto" -> {
                camera?.cameraControl?.enableTorch(false)
                currentCapture.flashMode = ImageCapture.FLASH_MODE_AUTO
            }
            "on" -> {
                camera?.cameraControl?.enableTorch(false)
                currentCapture.flashMode = ImageCapture.FLASH_MODE_ON
            }
            "torch" -> {
                if (camera?.cameraInfo?.hasFlashUnit() != true) {
                    throw CameraOperationException("FLASH_UNAVAILABLE", "This camera has no flash unit")
                }
                currentCapture.flashMode = ImageCapture.FLASH_MODE_OFF
                camera?.cameraControl?.enableTorch(true)
            }
            else -> throw CameraOperationException("INVALID_ARGUMENT", "Unknown flash mode: $mode")
        }
    }

    fun capture(
        callback: ((Result<Map<String, Any>>) -> Unit)?,
        automatic: Boolean = false,
    ) {
        try {
            checkActive()
            if (!capturing.compareAndSet(false, true)) {
                throw CameraOperationException("BUSY", "A capture is already in progress")
            }
            val currentCapture = imageCapture
                ?: throw CameraOperationException("INVALID_STATE", "Image capture is not ready")
            val previewCornersAtCapture = latestDisplayedCorners?.copyOf()
            stabilityTracker.onCaptured(System.nanoTime())
            emit(
                event(
                    eventName = "captureStarted",
                    state = "capturing",
                    extra = mapOf("automatic" to automatic),
                ),
            )

            val directory = File(context.cacheDir, "document_scanner_flutter/camera")
            directory.mkdirs()
            val outputFile = File(directory, "capture_${System.currentTimeMillis()}.jpg")
            val outputOptions = ImageCapture.OutputFileOptions.Builder(outputFile).build()
            currentCapture.takePicture(
                outputOptions,
                captureExecutor,
                object : ImageCapture.OnImageSavedCallback {
                    override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                        capturing.set(false)
                        val result = buildMap<String, Any> {
                            put("path", outputFile.absolutePath)
                            put("mimeType", "image/jpeg")
                            put("displayName", outputFile.name)
                            previewCornersAtCapture?.let { corners ->
                                put(
                                    "previewCorners",
                                    List(4) { index ->
                                        mapOf(
                                            "x" to corners[index * 2],
                                            "y" to corners[index * 2 + 1],
                                        )
                                    },
                                )
                            }
                        }
                        emit(
                            event(
                                eventName = "captureCompleted",
                                state = "detected",
                                extra = mapOf(
                                    "automatic" to automatic,
                                    "capture" to result,
                                ),
                            ),
                        )
                        mainHandler.post { callback?.invoke(Result.success(result)) }
                    }

                    override fun onError(exception: ImageCaptureException) {
                        capturing.set(false)
                        val error = CameraOperationException(
                            "CAPTURE_FAILED",
                            exception.message ?: "Camera capture failed",
                            exception,
                        )
                        emitError(error)
                        mainHandler.post { callback?.invoke(Result.failure(error)) }
                    }
                },
            )
        } catch (error: Throwable) {
            capturing.set(false)
            callback?.invoke(Result.failure(error)) ?: emitError(error)
        }
    }

    fun diagnostics(): Map<String, Any> = metrics.snapshot()

    fun stop() {
        if (disposed) return
        desiredPreview = false
        active = false
        pendingStart?.invoke(Result.failure(CameraOperationException("CANCELLED", "Camera start was cancelled")))
        pendingStart = null
        unbindOwnedUseCases()
        stabilityTracker.reset()
        lastHadDocument = false
        latestDisplayedCorners = null
        releaseTexture()
        emitCameraState("ready")
    }

    fun dispose() {
        if (disposed) return
        stop()
        disposed = true
        analysisExecutor.shutdownNow()
        captureExecutor.shutdownNow()
    }

    private fun bindUseCases() {
        val currentActivity = activity
        if (currentActivity == null) {
            failStart(CameraOperationException("NO_ACTIVITY", "Camera preview requires an attached Activity"))
            return
        }
        val lifecycleOwner = currentActivity as? LifecycleOwner
        if (lifecycleOwner == null) {
            failStart(CameraOperationException("INVALID_ACTIVITY", "Camera Activity must be a LifecycleOwner"))
            return
        }

        active = false
        previewWidth = 0
        previewHeight = 0
        previewCropWidth = 0
        previewCropHeight = 0
        previewTransformationReady = false
        previewAnnouncementPending = true

        val providerFuture = ProcessCameraProvider.getInstance(context)
        providerFuture.addListener(
            {
                try {
                    if (!desiredPreview || disposed) return@addListener
                    provider = providerFuture.get()
                    unbindOwnedUseCases()
                    metrics.reset()
                    @Suppress("DEPRECATION")
                    val targetRotation = currentActivity.windowManager.defaultDisplay.rotation

                    val nextPreview = Preview.Builder()
                        .setTargetRotation(targetRotation)
                        .build()
                    val nextAnalysis = ImageAnalysis.Builder()
                        .setTargetRotation(targetRotation)
                        .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build()
                    val nextCapture = ImageCapture.Builder()
                        .setTargetRotation(targetRotation)
                        .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
                        .build()

                    nextAnalysis.setAnalyzer(analysisExecutor, ::analyzeFrame)
                    nextPreview.setSurfaceProvider(mainExecutor) { request ->
                        val entry = ensureTexture()
                        previewWidth = request.resolution.width
                        previewHeight = request.resolution.height
                        request.setTransformationInfoListener(mainExecutor) { info ->
                            previewRotation = info.rotationDegrees
                            previewCropWidth = info.cropRect.width()
                            previewCropHeight = info.cropRect.height()
                            previewTransformationReady = true
                            completeStartIfReady()
                        }
                        entry.surfaceTexture().setDefaultBufferSize(previewWidth, previewHeight)
                        val surface = Surface(entry.surfaceTexture())
                        request.provideSurface(surface, mainExecutor) { surface.release() }
                        completeStartIfReady()
                    }

                    preview = nextPreview
                    imageAnalysis = nextAnalysis
                    imageCapture = nextCapture
                    val selector = CameraSelector.Builder()
                        .requireLensFacing(lensFacing)
                        .build()
                    camera = provider?.bindToLifecycle(
                        lifecycleOwner,
                        selector,
                        nextPreview,
                        nextAnalysis,
                        nextCapture,
                    )
                    active = true
                    completeStartIfReady()
                } catch (error: Throwable) {
                    failStart(
                        if (error is CameraOperationException) error else CameraOperationException(
                            "CAMERA_START_FAILED",
                            error.message ?: "Unable to start CameraX",
                            error,
                        ),
                    )
                }
            },
            mainExecutor,
        )
    }

    private fun analyzeFrame(image: ImageProxy) {
        val timestampNs = image.imageInfo.timestamp
        metrics.recordReceived(timestampNs)
        val startedNs = System.nanoTime()
        try {
            if (!active || disposed) return
            val planes = image.planes
            require(planes.size == 3) { "CameraX must deliver YUV_420_888 with three planes" }
            val rotation = image.imageInfo.rotationDegrees
            val resizeThreshold = options.number("previewResizeThreshold", 200.0).toInt().coerceAtLeast(0)
            val areaScaleMinFactor = options.number("previewAreaScaleMinFactor", 0.04).coerceIn(0.0, 1.0)
            val detection = processor.detectFrame(
                width = image.width,
                height = image.height,
                chromaPixelStride = planes[1].pixelStride,
                yBuffer = planes[0].buffer.slice(),
                yRowStride = planes[0].rowStride,
                uBuffer = planes[1].buffer.slice(),
                uRowStride = planes[1].rowStride,
                vBuffer = planes[2].buffer.slice(),
                vRowStride = planes[2].rowStride,
                rotationDegrees = rotation,
                resizeThreshold = resizeThreshold,
                areaScaleMinFactor = areaScaleMinFactor,
            )
            val swapsDimensions = rotation == 90 || rotation == 270
            val orientedWidth = if (swapsDimensions) image.height else image.width
            val orientedHeight = if (swapsDimensions) image.width else image.height
            val stability = stabilityTracker.update(
                detection.corners,
                orientedWidth,
                orientedHeight,
                timestampNs,
                autoCaptureEnabled,
            )
            val elapsedMs = (System.nanoTime() - startedNs) / 1_000_000.0
            metrics.recordProcessed(elapsedMs, detection.corners != null)

            val displayedCorners = stability.corners
            if (displayedCorners == null) {
                latestDisplayedCorners = null
                val rejectedForBlur = detection.source == "fft_rejected"
                // FFT is evaluated on a provisional warp for every frame. A
                // first-frame rejection may be a false quadrilateral, so only
                // expose a blur warning after this session had an accepted
                // document and subsequently lost focus/motion stability.
                if (rejectedForBlur && lastHadDocument && !blurWarningVisible) {
                    blurWarningVisible = true
                    emit(
                        event(
                            eventName = "documentBlurred",
                            state = "searching",
                            extra = frameMetadata(
                                orientedWidth,
                                orientedHeight,
                                elapsedMs,
                                stability,
                                detection,
                            ) + mapOf("documentBlurred" to true),
                        ),
                    )
                } else if (!rejectedForBlur && blurWarningVisible) {
                    blurWarningVisible = false
                    emit(
                        event(
                            eventName = "documentBlurCleared",
                            state = "searching",
                            extra = mapOf("documentBlurred" to false),
                        ),
                    )
                }
                if (lastHadDocument || stability.state == "lost") {
                    lastHadDocument = false
                    emit(
                        event(
                            eventName = "documentLost",
                            state = stability.state,
                            extra = frameMetadata(
                                orientedWidth,
                                orientedHeight,
                                elapsedMs,
                                stability,
                                detection,
                            ),
                        ),
                    )
                } else if (diagnosticsEnabled && metrics.framesProcessed() % 15L == 0L) {
                    emit(
                        event(
                            eventName = "diagnostics",
                            state = "searching",
                            extra = mapOf("diagnostics" to metrics.snapshot()),
                        ),
                    )
                }
                return
            }

            lastHadDocument = true
            blurWarningVisible = false
            latestDisplayedCorners = displayedCorners.copyOf()
            val cornerMaps = List(4) { index ->
                mapOf(
                    "x" to displayedCorners[index * 2],
                    "y" to displayedCorners[index * 2 + 1],
                )
            }
            emit(
                event(
                    eventName = "documentDetected",
                    state = stability.state,
                    extra = frameMetadata(
                        orientedWidth,
                        orientedHeight,
                        elapsedMs,
                        stability,
                        detection,
                    ) + mapOf("corners" to cornerMaps),
                ),
            )
            if (stability.shouldCapture) {
                mainHandler.post { capture(callback = null, automatic = true) }
            }
        } catch (error: Throwable) {
            emitError(error)
        } finally {
            image.close()
        }
    }

    private fun frameMetadata(
        orientedWidth: Int,
        orientedHeight: Int,
        elapsedMs: Double,
        stability: StabilityUpdate,
        detection: CascadeDetection? = null,
    ): Map<String, Any?> = buildMap {
        put("imageWidth", orientedWidth)
        put("imageHeight", orientedHeight)
        put("rotationDegrees", 0)
        put("mirrored", lensFacing == CameraSelector.LENS_FACING_FRONT)
        put("source", detection?.source ?: "cascade")
        put("confidence", detection?.confidence)
        put("fftScore", detection?.fftScore)
        put("stability", stability.progress)
        put("stableFrames", stability.stableFrames)
        put("processingTimeMs", elapsedMs)
        if (diagnosticsEnabled) put("diagnostics", metrics.snapshot())
    }

    private fun completeStartIfReady() {
        if (
            !active ||
            previewWidth <= 0 ||
            previewHeight <= 0 ||
            !previewTransformationReady
        ) return
        val info = previewInfo()
        if (previewAnnouncementPending) {
            previewAnnouncementPending = false
            emitCameraState("previewing", info)
        }
        val callback = pendingStart
        if (callback != null) {
            pendingStart = null
            callback(Result.success(info))
        }
    }

    private fun previewInfo(): Map<String, Any> {
        val entry = textureEntry
            ?: throw CameraOperationException("INVALID_STATE", "Camera Texture is unavailable")
        val transform = cameraXSurfaceTexturePreviewTransform(
            width = previewCropWidth.takeIf { it > 0 } ?: previewWidth,
            height = previewCropHeight.takeIf { it > 0 } ?: previewHeight,
            rotationDegrees = previewRotation,
        )
        return mapOf(
            "textureId" to entry.id(),
            "width" to transform.width,
            "height" to transform.height,
            "rotationDegrees" to transform.rotationDegrees,
            "mirrored" to transform.mirrored,
        )
    }

    private fun ensureTexture(): TextureRegistry.SurfaceTextureEntry {
        val existing = textureEntry
        if (existing != null) return existing
        return textureRegistry.createSurfaceTexture().also { textureEntry = it }
    }

    private fun releaseTexture() {
        textureEntry?.release()
        textureEntry = null
        previewWidth = 0
        previewHeight = 0
        previewRotation = 0
        previewCropWidth = 0
        previewCropHeight = 0
        previewTransformationReady = false
    }

    private fun unbindOwnedUseCases() {
        imageAnalysis?.clearAnalyzer()
        val owned = listOfNotNull(preview, imageAnalysis, imageCapture)
        if (owned.isNotEmpty()) provider?.unbind(*owned.toTypedArray())
        preview = null
        imageAnalysis = null
        imageCapture = null
        camera = null
    }

    private fun failStart(error: Throwable) {
        active = false
        val callback = pendingStart
        pendingStart = null
        emitError(error)
        callback?.invoke(Result.failure(error))
    }

    private fun emitCameraState(
        cameraState: String,
        preview: Map<String, Any>? = null,
    ) {
        emit(
            event(
                eventName = "cameraState",
                state = if (cameraState == "previewing") "searching" else "lost",
                extra = buildMap {
                    put("cameraState", cameraState)
                    if (preview != null) put("preview", preview)
                },
            ),
        )
    }

    private fun emitError(error: Throwable) {
        val typed = error as? CameraOperationException
        emit(
            event(
                eventName = "error",
                state = "error",
                extra = mapOf(
                    "code" to (typed?.code ?: "NATIVE_PROCESSING_ERROR"),
                    "message" to (error.message ?: "Native camera operation failed"),
                ),
            ),
        )
    }

    private fun event(
        eventName: String,
        state: String,
        extra: Map<String, Any?> = emptyMap(),
    ): Map<String, Any?> = buildMap {
        put("event", eventName)
        put("state", state)
        put("timestampMicros", System.nanoTime() / 1_000L)
        putAll(extra)
    }

    private fun checkUsable() {
        if (disposed) throw CameraOperationException("DISPOSED", "Camera session is disposed")
    }

    private fun checkActive() {
        checkUsable()
        if (!active) throw CameraOperationException("INVALID_STATE", "Camera preview is not active")
    }

    private fun Map<String, Any?>?.number(name: String, fallback: Double): Double =
        (this?.get(name) as? Number)?.toDouble() ?: fallback

    private fun Map<String, Any?>?.boolean(name: String, fallback: Boolean): Boolean =
        this?.get(name) as? Boolean ?: fallback
}

internal data class FlutterPreviewTransform(
    val width: Int,
    val height: Int,
    val rotationDegrees: Int,
    val mirrored: Boolean,
)

/**
 * CameraX writes crop, rotation, and front-camera mirroring into a SurfaceTexture transform.
 * Flutter applies that transform while sampling the external texture, so only the oriented layout
 * dimensions must be reported. Rotating or mirroring the Texture widget again double-transforms
 * the preview and makes motion appear inverted.
 */
internal fun cameraXSurfaceTexturePreviewTransform(
    width: Int,
    height: Int,
    rotationDegrees: Int,
): FlutterPreviewTransform {
    require(width > 0 && height > 0) { "Preview dimensions must be positive" }
    require(rotationDegrees in setOf(0, 90, 180, 270)) {
        "Preview rotation must be 0, 90, 180, or 270"
    }
    val swapsDimensions = rotationDegrees == 90 || rotationDegrees == 270
    return FlutterPreviewTransform(
        width = if (swapsDimensions) height else width,
        height = if (swapsDimensions) width else height,
        rotationDegrees = 0,
        mirrored = false,
    )
}

/** Debug-only aggregate; image data and paths never enter diagnostics. */
internal class CameraMetrics {
    private val received = AtomicLong()
    private val processed = AtomicLong()
    private val dropped = AtomicLong()
    private val candidates = AtomicLong()
    private val totalProcessingMicros = AtomicLong()
    private val firstCameraTimestampNs = AtomicLong()
    private val lastCameraTimestampNs = AtomicLong()
    private val minimumFrameDeltaNs = AtomicLong(Long.MAX_VALUE)
    private val startedNs = AtomicLong(System.nanoTime())

    fun reset() {
        received.set(0)
        processed.set(0)
        dropped.set(0)
        candidates.set(0)
        totalProcessingMicros.set(0)
        firstCameraTimestampNs.set(0)
        lastCameraTimestampNs.set(0)
        minimumFrameDeltaNs.set(Long.MAX_VALUE)
        startedNs.set(System.nanoTime())
    }

    fun recordReceived(timestampNs: Long) {
        received.incrementAndGet()
        firstCameraTimestampNs.compareAndSet(0, timestampNs)
        val previous = lastCameraTimestampNs.getAndSet(timestampNs)
        if (previous <= 0 || timestampNs <= previous) return
        val delta = timestampNs - previous
        minimumFrameDeltaNs.accumulateAndGet(delta, ::minOf)
        val baseline = minimumFrameDeltaNs.get()
        if (baseline != Long.MAX_VALUE && delta > baseline * 3 / 2) {
            val estimated = (delta.toDouble() / baseline).roundToLong() - 1
            if (estimated > 0) dropped.addAndGet(estimated)
        }
    }

    fun recordProcessed(processingTimeMs: Double, foundCandidate: Boolean) {
        processed.incrementAndGet()
        totalProcessingMicros.addAndGet((processingTimeMs * 1000).roundToLong())
        if (foundCandidate) candidates.incrementAndGet()
    }

    fun framesProcessed(): Long = processed.get()

    fun snapshot(): Map<String, Any> {
        val receivedValue = received.get()
        val processedValue = processed.get()
        val firstTimestamp = firstCameraTimestampNs.get()
        val lastTimestamp = lastCameraTimestampNs.get()
        val cameraSeconds = (lastTimestamp - firstTimestamp).coerceAtLeast(0) / 1_000_000_000.0
        val analysisSeconds = (System.nanoTime() - startedNs.get()).coerceAtLeast(1) / 1_000_000_000.0
        return mapOf(
            "framesReceived" to receivedValue,
            "framesProcessed" to processedValue,
            "framesDropped" to dropped.get(),
            "candidatesFound" to candidates.get(),
            "cameraFps" to if (cameraSeconds > 0) receivedValue / cameraSeconds else 0.0,
            "analysisFps" to processedValue / analysisSeconds,
            "averageProcessingTimeMs" to if (processedValue > 0) {
                totalProcessingMicros.get() / processedValue / 1000.0
            } else {
                0.0
            },
            "backpressureStrategy" to "KEEP_ONLY_LATEST",
        )
    }
}
