package br.com.dinheironanota.document_scanner_flutter

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.io.BufferedOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.util.UUID
import java.util.concurrent.TimeUnit

internal object CloudUploadQueue {
    fun enqueue(context: Context, imagePath: String, destination: String): String {
        val source = File(imagePath)
        require(source.isFile) { "Processed image does not exist: $imagePath" }
        val endpoint = validateEndpoint(destination)
        val id = UUID.randomUUID().toString()
        val queueDirectory = File(context.filesDir, "document_scanner_flutter/upload_queue")
        check(queueDirectory.exists() || queueDirectory.mkdirs()) { "Unable to create upload queue" }
        val queuedFile = File(queueDirectory, "$id.jpg")
        source.copyTo(queuedFile, overwrite = false)

        val request = OneTimeWorkRequestBuilder<CloudUploadWorker>()
            .setConstraints(
                Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build(),
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.SECONDS)
            .setInputData(
                Data.Builder()
                    .putString(CloudUploadWorker.KEY_FILE_PATH, queuedFile.absolutePath)
                    .putString(CloudUploadWorker.KEY_DESTINATION, endpoint)
                    .build(),
            )
            .addTag(CloudUploadWorker.TAG)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            "document-upload-$id",
            ExistingWorkPolicy.KEEP,
            request,
        )
        return request.id.toString()
    }

    private fun validateEndpoint(raw: String): String {
        val value = raw.trim()
        val uri = runCatching { URI(value) }.getOrNull()
        require(uri != null && uri.host != null && uri.scheme in setOf("https", "http")) {
            "Cloud destination must be an HTTP(S) upload endpoint or webhook"
        }
        return value
    }
}

/** Durable multipart upload. The file is copied to app storage before work is scheduled. */
class CloudUploadWorker(
    appContext: Context,
    parameters: WorkerParameters,
) : CoroutineWorker(appContext, parameters) {
    override suspend fun doWork(): Result {
        val path = inputData.getString(KEY_FILE_PATH) ?: return Result.failure(error("Missing file path"))
        val destination = inputData.getString(KEY_DESTINATION)
            ?: return Result.failure(error("Missing destination"))
        val file = File(path)
        if (!file.isFile) return Result.failure(error("Queued image no longer exists"))

        val boundary = "DocumentScanner-${UUID.randomUUID()}"
        val connection = (URI(destination).toURL().openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 30_000
            readTimeout = 45_000
            doOutput = true
            useCaches = false
            setChunkedStreamingMode(64 * 1024)
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
            setRequestProperty("Idempotency-Key", id.toString())
        }

        return try {
            BufferedOutputStream(connection.outputStream).use { output ->
                output.write("--$boundary\r\n".toByteArray())
                output.write(
                    "Content-Disposition: form-data; name=\"file\"; filename=\"${file.name}\"\r\n".toByteArray(),
                )
                output.write("Content-Type: image/jpeg\r\n\r\n".toByteArray())
                file.inputStream().use { input -> input.copyTo(output, 64 * 1024) }
                output.write("\r\n--$boundary--\r\n".toByteArray())
            }
            val status = connection.responseCode
            (if (status in 200..299) connection.inputStream else connection.errorStream)?.use { it.readBytes() }
            when {
                status in 200..299 -> {
                    file.delete()
                    Result.success(Data.Builder().putInt(KEY_HTTP_STATUS, status).build())
                }
                status == 408 || status == 429 || status >= 500 -> Result.retry()
                else -> {
                    file.delete()
                    Result.failure(error("Upload rejected with HTTP $status"))
                }
            }
        } catch (error: Exception) {
            if (runAttemptCount < MAX_ATTEMPTS) Result.retry()
            else {
                file.delete()
                Result.failure(error(error.message ?: "Upload failed"))
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun error(message: String): Data = Data.Builder().putString(KEY_ERROR, message).build()

    companion object {
        const val TAG = "document-scanner-cloud-upload"
        const val KEY_FILE_PATH = "filePath"
        const val KEY_DESTINATION = "destination"
        const val KEY_HTTP_STATUS = "httpStatus"
        const val KEY_ERROR = "error"
        private const val MAX_ATTEMPTS = 5
    }
}
