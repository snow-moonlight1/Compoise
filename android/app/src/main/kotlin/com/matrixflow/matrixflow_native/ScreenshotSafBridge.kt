package com.matrixflow.matrixflow_native

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** Temporary SAF grants and image paths stay in this flow. No logging. */
internal class ScreenshotSafBridge(private val activity: Activity, channel: MethodChannel) :
    MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var picker: MethodChannel.Result? = null
    private var request = 4200
    private var activeRequest = -1
    private var session: Session? = null
    @Volatile private var destroyed = false
    private class Session(val id: String, val directory: File, val uris: List<Uri>) {
        val stage = ScreenshotPngStage(directory)
        var next = 0
    }
    init {
        channel.setMethodCallHandler(this)
        worker.execute {
            try { ScreenshotTempFiles(activity.cacheDir).purge() }
            catch (_: Exception) { /* The explicit availability check retries and reports failure. */ }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "cleanup" -> {
                if (picker != null || session?.stage?.cancelled == false) { result.error("busy", "Unavailable", null); return }
                background(result) { ScreenshotTempFiles(activity.cacheDir).purge(); null }
            }
            "pick" -> {
                if (destroyed || session != null || picker != null) { result.error("busy", "Unavailable", null); return }
                picker = result
                activeRequest = request++
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    type = "image/png"
                    addCategory(Intent.CATEGORY_OPENABLE)
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                try { activity.startActivityForResult(intent, activeRequest) }
                catch (_: Exception) { picker = null; result.success(mapOf("error" to "screenshotImportUnavailable")) }
            }
            "cancelPick" -> { cancelPicker(); session?.stage?.stop(); result.success(null) }
            "stage" -> {
                val current = matching(call)
                val index = call.argument<Int>("index")
                if (current == null || index == null) { result.error("state", "SafRead", null); return }
                background(result) {
                    if (index != current.next++ || index !in current.uris.indices) throw ScreenshotLimit("SafRead")
                    try {
                        val stream = activity.contentResolver.openInputStream(current.uris[index]) ?: throw ScreenshotLimit("SafRead")
                        val count = current.stage.stage(index, stream)
                        mapOf("path" to current.stage.file(index).absolutePath, "bytes" to count)
                    } catch (error: Exception) {
                        mapOf("error" to "screenshotImport${(error as? ScreenshotLimit)?.code ?: "SafRead"}")
                    }
                }
            }
            "release" -> {
                val current = matching(call); val index = call.argument<Int>("index")
                if (current == null || index == null) { result.error("state", "CleanupFailed", null); return }
                background(result) {
                    val file = current.stage.file(index)
                    if (file.exists() && !file.delete()) throw ScreenshotLimit("CleanupFailed")
                    null
                }
            }
            "close" -> {
                val current = matching(call)
                if (current == null) { result.success(null); return }
                current.stage.stop()
                background(result) { ScreenshotTempFiles(activity.cacheDir).remove(current.directory); null }
                // Keep session until cleanup finishes, so a second picker cannot
                // overlap. Set to null on the worker completion below.
            }
            else -> result.notImplemented()
        }
    }

    private fun matching(call: MethodCall): Session? = session?.takeIf { it.id == call.argument<String>("session") }
    private fun cancelPicker() {
        val pending = picker
        picker = null
        val requestCode = activeRequest
        activeRequest = -1
        if (requestCode >= 0) {
            try { activity.finishActivity(requestCode) } catch (_: Exception) { }
        }
        pending?.success(null)
    }
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute {
            try {
                val value = work()
                main.post {
                    // Close removes the directory; failed cleanup keeps ownership.
                    if (session?.directory?.exists() == false) session = null
                    if (!destroyed) result.success(value)
                }
            } catch (error: Exception) {
                main.post { if (!destroyed) result.error("screenshot", (error as? ScreenshotLimit)?.code ?: "SafRead", null) }
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != activeRequest || picker == null) return false
        val result = picker!!; picker = null; activeRequest = -1
        if (resultCode != Activity.RESULT_OK || data == null) { result.success(null); return true }
        val uris = ArrayList<Uri>()
        val clip = data.clipData
        val count = clip?.itemCount ?: if (data.data != null) 1 else 0
        if (count !in 1..10) { result.success(mapOf("error" to "screenshotImportSafCountLimit")); return true }
        for (index in 0 until count) {
            val uri = clip?.getItemAt(index)?.uri ?: data.data!!
            if (uri.scheme != "content") { result.success(mapOf("error" to "screenshotImportSafRead")); return true }
            uris.add(uri)
        }
        try {
            val directory = ScreenshotTempFiles(activity.cacheDir).create()
            val current = Session(UUID.randomUUID().toString(), directory, uris)
            session = current
            result.success(mapOf("session" to current.id, "count" to count))
        } catch (_: Exception) { result.success(mapOf("error" to "screenshotImportCleanupFailed")) }
        return true
    }

    fun destroy() {
        destroyed = true
        cancelPicker()
        val current = session
        current?.stage?.stop()
        worker.execute {
            try { if (current != null) ScreenshotTempFiles(activity.cacheDir).remove(current.directory) }
            catch (_: Exception) { /* Only this module's leftovers are retried at next startup. */ }
        }
        worker.shutdown()
    }
}
