package br.com.dinheironanota.document_scanner_flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.io.FileNotFoundException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** Static-image Android implementation for the first plugin migration phase. */
class DocumentScannerFlutterPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {
    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPickerResult: MethodChannel.Result? = null
    private val pendingOperations = ConcurrentHashMap.newKeySet<MethodChannel.Result>()
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
    private val processor by lazy { NativeDocumentProcessor() }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
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
            "dispose" -> result.success(null)
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
        "pluginVersion" to "0.1.0",
        "opencvVersion" to "4.12.0",
        "detectorAvailable" to true,
        "staticImageSupported" to true,
        "cameraPreviewSupported" to false,
    )

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
    }

    override fun onDetachedFromActivityForConfigChanges() = detachActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detachActivity()

    private fun detachActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        pendingPickerResult?.error("NO_ACTIVITY", "Activity detached while picking an image", null)
        pendingPickerResult = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
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
        const val PICK_IMAGE_REQUEST = 9142
    }
}
