package br.com.dinheironanota.document_scanner_flutter

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** Flutter bridge for static scanning and the native CameraX scanner. */
class DocumentScannerFlutterPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener,
    EventChannel.StreamHandler {
    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var applicationContext: Context
    private lateinit var textureRegistry: TextureRegistry
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPickerResult: MethodChannel.Result? = null
    private var pendingCameraPermissionResult: MethodChannel.Result? = null
    private var pendingCameraOptions: Map<String, Any?>? = null
    private var eventSink: EventChannel.EventSink? = null
    private var cameraSession: CameraSession? = null
    private val pendingOperations = ConcurrentHashMap.newKeySet<MethodChannel.Result>()
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    private val processor by lazy { NativeDocumentProcessor() }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        textureRegistry = binding.textureRegistry
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL_NAME)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getNativeStatus", "initialize" -> result.success(nativeStatus())
            "pickImage" -> pickImage(result)
            "detectDocument" -> runAsync(result) {
                val path = requiredPath(call)
                processor.detect(path, call.argument<Map<String, Any?>>("options"))
            }
            "cropDocument" -> runAsync(result) {
                val path = requiredPath(call)
                val corners = call.argument<List<Map<String, Number>>>("corners")
                    ?: throw IllegalArgumentException("corners is required")
                processor.crop(
                    sourcePath = path,
                    corners = corners,
                    options = call.argument<Map<String, Any?>>("options"),
                    outputDirectory = applicationContext.cacheDir,
                )
            }
            "applyFilter" -> runAsync(result) {
                val path = requiredPath(call)
                val outputPath = call.argument<String>("outputPath")
                    ?.takeIf { it.isNotBlank() }
                    ?: throw IllegalArgumentException("outputPath is required")
                val filter = call.argument<String>("filter")
                    ?: throw IllegalArgumentException("filter is required")
                processor.applyFilter(
                    sourcePath = path,
                    outputPath = outputPath,
                    filter = filter,
                    outputFormat = call.argument<String>("outputFormat") ?: "jpeg",
                    jpegQuality = (call.argument<Number>("jpegQuality")?.toInt() ?: 92)
                        .coerceIn(1, 100),
                )
            }
            "recognizeText" -> runAsync(result) {
                recognizeText(requiredPath(call))
            }
            "startPreview" -> startPreview(call, result)
            "stopPreview" -> cameraCommand(result) {
                cameraSession?.stop()
                null
            }
            "pausePreview" -> cameraCommand(result) {
                requiredCameraSession().pause()
                null
            }
            "resumePreview" -> resumePreview(result)
            "switchCamera" -> switchCamera(result)
            "setFlash" -> cameraCommand(result) {
                val mode = call.argument<String>("mode")
                    ?: throw IllegalArgumentException("mode is required")
                requiredCameraSession().setFlashMode(mode)
                null
            }
            "setAutoCapture" -> cameraCommand(result) {
                val enabled = call.argument<Boolean>("enabled")
                    ?: throw IllegalArgumentException("enabled is required")
                requiredCameraSession().setAutoCapture(enabled)
                null
            }
            "capture" -> capture(result)
            "getDiagnostics" -> cameraCommand(result) {
                requiredCameraSession().diagnostics()
            }
            "dispose" -> {
                disposeCamera()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun requiredPath(call: MethodCall): String {
        return call.argument<String>("imagePath")
            ?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("imagePath is required")
    }

    private fun nativeStatus(): Map<String, Any> = mapOf(
        "platform" to "android",
        "pluginVersion" to "0.2.0",
        "opencvVersion" to "4.12.0",
        "detectorAvailable" to true,
        "staticImageSupported" to true,
        "cameraPreviewSupported" to true,
    )

    private fun recognizeText(imagePath: String): Map<String, Any> {
        val startedAt = SystemClock.elapsedRealtime()
        val file = File(imagePath)
        if (!file.exists()) throw FileNotFoundException(imagePath)
        val decoded = BitmapFactory.decodeFile(imagePath)
            ?: throw IllegalArgumentException("Image could not be decoded")
        val bitmap = ExifOrientation.apply(file, decoded)
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        return try {
            val recognized = Tasks.await(recognizer.process(InputImage.fromBitmap(bitmap, 0)))
            val imageWidth = bitmap.width.toDouble().coerceAtLeast(1.0)
            val imageHeight = bitmap.height.toDouble().coerceAtLeast(1.0)
            val languages = linkedSetOf<String>()
            val blocks = recognized.textBlocks.map { block ->
                block.lines.mapTo(languages) { it.recognizedLanguage }
                val bounds = block.boundingBox
                mapOf(
                    "text" to block.text,
                    "left" to ((bounds?.left ?: 0) / imageWidth).coerceIn(0.0, 1.0),
                    "top" to ((bounds?.top ?: 0) / imageHeight).coerceIn(0.0, 1.0),
                    "width" to ((bounds?.width() ?: 0) / imageWidth).coerceIn(0.0, 1.0),
                    "height" to ((bounds?.height() ?: 0) / imageHeight).coerceIn(0.0, 1.0),
                )
            }
            mapOf(
                "text" to recognized.text,
                "blocks" to blocks,
                "languages" to languages.filter { it.isNotBlank() },
                "durationMilliseconds" to SystemClock.elapsedRealtime() - startedAt,
            )
        } finally {
            recognizer.close()
            bitmap.recycle()
        }
    }

    private fun startPreview(call: MethodCall, result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("NO_ACTIVITY", "Camera preview requires an attached Activity", null)
            return
        }
        val options = call.argument<Map<String, Any?>>("options")
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingCameraPermissionResult != null) {
                result.error("BUSY", "A camera permission request is already active", null)
                return
            }
            pendingCameraPermissionResult = result
            pendingCameraOptions = options
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.CAMERA),
                CAMERA_PERMISSION_REQUEST,
            )
            return
        }
        startCameraWithPermission(activity, options, result)
    }

    private fun startCameraWithPermission(
        activity: Activity,
        options: Map<String, Any?>?,
        result: MethodChannel.Result,
    ) {
        val session = cameraSession ?: CameraSession(
            context = applicationContext,
            textureRegistry = textureRegistry,
            processor = processor,
            mainHandler = mainHandler,
            emit = ::emitCameraEvent,
        ).also { cameraSession = it }
        session.start(activity, options) { outcome -> completeCameraResult(result, outcome) }
    }

    private fun resumePreview(result: MethodChannel.Result) {
        try {
            requiredCameraSession().resume { outcome -> completeCameraResult(result, outcome) }
        } catch (error: Throwable) {
            returnCameraError(result, error)
        }
    }

    private fun switchCamera(result: MethodChannel.Result) {
        try {
            requiredCameraSession().switchCamera { outcome -> completeCameraResult(result, outcome) }
        } catch (error: Throwable) {
            returnCameraError(result, error)
        }
    }

    private fun capture(result: MethodChannel.Result) {
        try {
            requiredCameraSession().capture(
                callback = { outcome -> completeCameraResult(result, outcome) },
                automatic = false,
            )
        } catch (error: Throwable) {
            returnCameraError(result, error)
        }
    }

    private fun cameraCommand(result: MethodChannel.Result, command: () -> Any?) {
        try {
            result.success(command())
        } catch (error: Throwable) {
            returnCameraError(result, error)
        }
    }

    private fun requiredCameraSession(): CameraSession = cameraSession
        ?: throw CameraOperationException("INVALID_STATE", "Camera preview has not been started")

    private fun completeCameraResult(
        result: MethodChannel.Result,
        outcome: Result<Map<String, Any>>,
    ) {
        mainHandler.post {
            outcome.fold(
                onSuccess = result::success,
                onFailure = { error -> returnCameraError(result, error) },
            )
        }
    }

    private fun returnCameraError(result: MethodChannel.Result, error: Throwable) {
        val code = when (error) {
            is CameraOperationException -> error.code
            is IllegalArgumentException -> "INVALID_ARGUMENT"
            else -> "NATIVE_PROCESSING_ERROR"
        }
        result.error(code, error.message ?: "Native camera operation failed", null)
    }

    private fun emitCameraEvent(event: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(event) }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun runAsync(result: MethodChannel.Result, operation: () -> Any?) {
        pendingOperations.add(result)
        executor.execute {
            try {
                val value = operation()
                mainHandler.post {
                    if (pendingOperations.remove(result)) result.success(value)
                }
            } catch (error: Throwable) {
                val code = when (error) {
                    is IllegalArgumentException -> "INVALID_ARGUMENT"
                    is FileNotFoundException -> "FILE_NOT_FOUND"
                    else -> "NATIVE_PROCESSING_ERROR"
                }
                mainHandler.post {
                    if (pendingOperations.remove(result)) {
                        result.error(code, error.message ?: "Native scanner operation failed", null)
                    }
                }
            }
        }
    }

    private fun pickImage(result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("NO_ACTIVITY", "Image picking requires an attached Activity", null)
            return
        }
        if (pendingPickerResult != null) {
            result.error("BUSY", "An image picker request is already active", null)
            return
        }
        pendingPickerResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
        }
        activity.startActivityForResult(intent, PICK_IMAGE_REQUEST)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_IMAGE_REQUEST) return false
        val result = pendingPickerResult ?: return true
        pendingPickerResult = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return true
        }
        runAsync(result) { copyPickedImage(data.data!!) }
        return true
    }

    private fun copyPickedImage(uri: Uri): Map<String, Any?> {
        val resolver = applicationContext.contentResolver
        val mimeType = resolver.getType(uri)
        val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType) ?: "img"
        val outputDirectory = File(applicationContext.cacheDir, "document_scanner_flutter/input")
        outputDirectory.mkdirs()
        val destination = File(outputDirectory, "picked_${System.currentTimeMillis()}.$extension")
        resolver.openInputStream(uri)?.use { input ->
            destination.outputStream().use { output -> input.copyTo(output) }
        } ?: throw FileNotFoundException("Unable to open selected image")

        var displayName: String? = null
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) displayName = cursor.getString(0)
        }
        return mapOf(
            "path" to destination.absolutePath,
            "mimeType" to mimeType,
            "displayName" to displayName,
        )
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
        cameraSession?.attachActivity(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity(preservePreviewIntent = true)
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detachActivity(preservePreviewIntent = false)

    private fun detachActivity(preservePreviewIntent: Boolean) {
        cameraSession?.detachActivity(preservePreviewIntent)
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        pendingPickerResult?.error("NO_ACTIVITY", "Activity detached while picking an image", null)
        pendingPickerResult = null
        pendingCameraPermissionResult?.error(
            "NO_ACTIVITY",
            "Activity detached while requesting camera permission",
            null,
        )
        pendingCameraPermissionResult = null
        pendingCameraOptions = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != CAMERA_PERMISSION_REQUEST) return false
        val result = pendingCameraPermissionResult ?: return true
        val options = pendingCameraOptions
        pendingCameraPermissionResult = null
        pendingCameraOptions = null
        val activity = activityBinding?.activity
        if (activity == null) {
            result.error("NO_ACTIVITY", "Activity detached during camera permission request", null)
        } else if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startCameraWithPermission(activity, options, result)
        } else {
            result.error("CAMERA_PERMISSION_DENIED", "Camera permission was denied", null)
        }
        return true
    }

    private fun disposeCamera() {
        cameraSession?.dispose()
        cameraSession = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        disposeCamera()
        pendingCameraPermissionResult?.error("ENGINE_DETACHED", "Flutter engine detached", null)
        pendingCameraPermissionResult = null
        pendingCameraOptions = null
        pendingPickerResult?.error("ENGINE_DETACHED", "Flutter engine detached", null)
        pendingPickerResult = null
        pendingOperations.toList().forEach { result ->
            if (pendingOperations.remove(result)) {
                result.error("ENGINE_DETACHED", "Flutter engine detached", null)
            }
        }
        executor.shutdownNow()
    }

    private companion object {
        const val CHANNEL_NAME = "document_scanner_flutter"
        const val EVENT_CHANNEL_NAME = "document_scanner_flutter/events"
        const val PICK_IMAGE_REQUEST = 9142
        const val CAMERA_PERMISSION_REQUEST = 9143
    }
}
