package com.matrixflow.matrixflow_native

import java.io.File
import java.io.InputStream
import java.nio.ByteBuffer
import java.util.UUID

internal class ScreenshotLimit(val code: String) : Exception()

/** Pure JVM bounded reader, shared by SAF and deterministic stream tests. */
internal class ScreenshotPngStage(private val directory: File) {
    companion object {
        const val FILE_BYTES = 16L * 1024 * 1024
        const val BATCH_BYTES = 48L * 1024 * 1024
        const val BATCH_PIXELS = 24L * 1024 * 1024
    }
    var bytesRead = 0L; private set
    var pixels = 0L; private set
    @Volatile var cancelled = false
    @Volatile private var activeStream: InputStream? = null

    fun stop() {
        cancelled = true
        try { activeStream?.close() } catch (_: Exception) { }
    }

    fun file(index: Int): File {
        if (index !in 0..9) throw ScreenshotLimit("SafCountLimit")
        return File(directory, "image-$index.png")
    }

    fun stage(index: Int, stream: InputStream): Long {
        val output = file(index)
        var localBytes = 0L
        activeStream = stream
        fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            if (cancelled) throw ScreenshotLimit("SafCancelled")
            val fileLeft = FILE_BYTES - localBytes
            val batchLeft = BATCH_BYTES - bytesRead
            // No sentinel over-read. A stream exactly at the limit is rejected
            // conservatively because its EOF cannot be checked within the cap.
            if (fileLeft <= 0) throw ScreenshotLimit("SafFileLimit")
            if (batchLeft <= 0) throw ScreenshotLimit("SafBatchLimit")
            val count = stream.read(buffer, offset, minOf(length.toLong(), fileLeft, batchLeft).toInt())
            if (count == 0) throw ScreenshotLimit("SafRead")
            if (count > 0) { localBytes += count; bytesRead += count }
            return count
        }
        try {
            stream.use {
                val header = ByteArray(33)
                var offset = 0
                while (offset < header.size) {
                    val count = read(header, offset, header.size - offset)
                    if (count < 0) throw ScreenshotLimit("SafPng")
                    offset += count
                }
                val signature = byteArrayOf(137.toByte(), 80, 78, 71, 13, 10, 26, 10)
                if (!header.copyOfRange(0, 8).contentEquals(signature)) throw ScreenshotLimit("SafPng")
                val data = ByteBuffer.wrap(header)
                if (data.getInt(8) != 13 || data.getInt(12) != 0x49484452) throw ScreenshotLimit("SafPng")
                val width = data.getInt(16).toLong(); val height = data.getInt(20).toLong()
                val area = width * height
                if (width !in 1..4096 || height !in 1..8192 || area > 12L * 1024 * 1024 ||
                    pixels + area > BATCH_PIXELS) throw ScreenshotLimit("SafPixelLimit")
                pixels += area
                output.outputStream().use { sink ->
                    sink.write(header)
                    val buffer = ByteArray(32 * 1024)
                    while (true) {
                        val count = read(buffer, 0, buffer.size)
                        if (count < 0) break
                        sink.write(buffer, 0, count)
                    }
                }
            }
            if (cancelled) throw ScreenshotLimit("SafCancelled")
            return localBytes
        } catch (error: Exception) {
            if (output.exists() && !output.delete()) throw ScreenshotLimit("CleanupFailed")
            throw error
        } finally { activeStream = null }
    }
}

/** Deletes only this module's session directories, never file_picker caches. */
internal class ScreenshotTempFiles(cacheDir: File) {
    private val root = File(cacheDir.canonicalFile, "wp17-screenshot-import")
    private val pattern = Regex("session-[a-f0-9-]{36}")
    init {
        if (root.canonicalFile != root.absoluteFile || root.canonicalFile.parentFile != cacheDir.canonicalFile ||
            (!root.exists() && !root.mkdir()) || !root.isDirectory) {
            throw ScreenshotLimit("CleanupFailed")
        }
    }
    fun create(): File = File(root, "session-${UUID.randomUUID()}").also {
        if (!it.mkdir()) throw ScreenshotLimit("CleanupFailed")
    }
    fun purge() {
        val entries = root.listFiles() ?: throw ScreenshotLimit("CleanupFailed")
        entries.filter { pattern.matches(it.name) }.forEach { remove(it) }
    }
    fun remove(directory: File) {
        if (directory.parentFile.canonicalFile != root.canonicalFile || !pattern.matches(directory.name)) {
            throw ScreenshotLimit("CleanupFailed")
        }
        fun erase(file: File) {
            if (file.canonicalPath != file.absolutePath) {
                // Refuse to follow symlinks or aliases outside owned storage.
                throw ScreenshotLimit("CleanupFailed")
            }
            if (file.isDirectory) (file.listFiles() ?: throw ScreenshotLimit("CleanupFailed")).forEach { erase(it) }
            if (file.exists() && !file.delete()) throw ScreenshotLimit("CleanupFailed")
        }
        erase(directory)
    }
}
