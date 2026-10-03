package com.matrixflow.matrixflow_native

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors

/** Optional, APK-local official assets. No download or external-storage access. */
class OcrAssetsBridge(private val context: Context, private val channel: MethodChannel) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val names = setOf(
        "ncnn/ppocrv5_dict.txt", "ncnn/PP_OCRv5_mobile_det.ncnn.param",
        "ncnn/PP_OCRv5_mobile_det.ncnn.bin", "ncnn/PP_OCRv5_mobile_rec.ncnn.param",
        "ncnn/PP_OCRv5_mobile_rec.ncnn.bin", "deployed.json",
        "licenses/APACHE-2.0.txt", "licenses/ncnn-BSD-3-Clause.txt", "licenses/stb-LICENSE.txt",
        "licenses/PP-OCRv5_mobile_det.MODEL_CARD.md", "licenses/PP-OCRv5_mobile_rec.MODEL_CARD.md",
        "licenses/THIRD_PARTY_OCR_NOTICES.md",
    )

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "prepare") result.notImplemented()
            else worker.execute {
                try {
                    val root = prepare()
                    main.post { result.success(root) }
                } catch (_: Exception) {
                    // Do not put filenames, source images or provider URIs in logs.
                    main.post { result.error("OCR_ASSETS", "Packaged OCR assets could not be verified", null) }
                }
            }
        }
    }

    private fun digest(file: File): String {
        val hash = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(32768)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                hash.update(buffer, 0, count)
            }
        }
        return hash.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }

    private fun owned(parent: File, name: String): File {
        val file = File(parent, name)
        check(file.canonicalPath == file.absolutePath) { "Asset path alias" }
        return file
    }

    private fun matches(root: File, files: JSONObject): Boolean = names.all { name ->
        val file = owned(root, name)
        val record = files.getJSONObject(name)
        file.isFile && file.length() == record.getLong("bytes") && digest(file) == record.getString("sha256")
    }

    private fun prepare(): String? {
        val manifestBytes = try {
            context.assets.open("wp17-ocr/bundle-manifest.json").use { it.readBytes() }
        } catch (_: FileNotFoundException) { return null }
        check(manifestBytes.size <= 65536)
        val manifest = JSONObject(String(manifestBytes, Charsets.UTF_8))
        check(manifest.getInt("schema") == 1 && manifest.getString("modelSource") == "official")
        val files = manifest.getJSONObject("files")
        check(files.keys().asSequence().toSet() == names)
        check(names.sumOf { files.getJSONObject(it).getLong("bytes") } < 16 * 1024 * 1024)
        for (name in names) {
            val record = files.getJSONObject(name)
            check(record.getLong("bytes") > 0)
            check(record.getString("sha256").matches(Regex("[0-9a-f]{64}")))
        }
        val parent = context.filesDir.canonicalFile
        val root = owned(parent, "wp17-ocr")
        if (matches(root, files)) return root.absolutePath
        val stage = owned(parent, ".wp17-ocr-stage-${UUID.randomUUID()}")
        val backup = owned(parent, ".wp17-ocr-backup-${UUID.randomUUID()}")
        check(stage.mkdir())
        try {
            for (name in names) {
                val output = owned(stage, name)
                check(output.parentFile!!.isDirectory || output.parentFile!!.mkdirs())
                context.assets.open("wp17-ocr/$name").use { input ->
                    output.outputStream().use { input.copyTo(it, 32768) }
                }
            }
            owned(stage, "bundle-manifest.json").writeBytes(manifestBytes)
            check(matches(stage, files))
            val hadRoot = root.exists()
            if (hadRoot) check(root.renameTo(backup))
            if (!stage.renameTo(root)) {
                if (hadRoot) check(backup.renameTo(root))
                error("Asset install failed")
            }
            if (hadRoot) check(backup.deleteRecursively())
            return root.absolutePath
        } finally {
            if (stage.exists()) check(stage.deleteRecursively())
        }
    }

    fun destroy() {
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }
}
