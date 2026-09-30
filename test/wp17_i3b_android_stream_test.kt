package com.matrixflow.matrixflow_native

import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.file.Files

private fun header(width: Int = 400, height: Int = 400): ByteArray {
    val bytes = ByteArray(33)
    byteArrayOf(137.toByte(), 80, 78, 71, 13, 10, 26, 10).copyInto(bytes)
    ByteBuffer.wrap(bytes).apply { putInt(8, 13); putInt(12, 0x49484452); putInt(16, width); putInt(20, height) }
    return bytes
}
private class SyntheticStream(val length: Long, private val first: ByteArray = header()) : InputStream() {
    var actual = 0L
    var closed = false
    var afterRead: (() -> Unit)? = null
    override fun read(): Int = throw AssertionError("Reader must use bounded chunks")
    override fun read(buffer: ByteArray, offset: Int, requested: Int): Int {
        if (actual >= length) return -1
        val count = minOf(requested.toLong(), length - actual).toInt()
        for (i in 0 until count) buffer[offset + i] = if (actual + i < first.size) first[(actual + i).toInt()] else 0
        actual += count; afterRead?.invoke(); return count
    }
    override fun close() { closed = true }
}
private fun fails(code: String, operation: () -> Unit) {
    try { operation(); error("Expected $code") }
    catch (error: ScreenshotLimit) { check(error.code == code) { "${error.code} != $code" } }
}

fun main() {
    val cache = Files.createTempDirectory("wp17-i3b-stream-").toFile()
    val owned = ScreenshotTempFiles(cache)
    try {
        val smallDir = owned.create(); val small = ScreenshotPngStage(smallDir)
        val bytes = header() + ByteArray(500)
        check(small.stage(0, ByteArrayInputStream(bytes)) == bytes.size.toLong())
        check(small.file(0).readBytes().contentEquals(bytes))
        owned.remove(smallDir)

        for (size in listOf(ScreenshotPngStage.FILE_BYTES, ScreenshotPngStage.FILE_BYTES + 1000000)) {
            val dir = owned.create(); val stage = ScreenshotPngStage(dir); val stream = SyntheticStream(size)
            fails("SafFileLimit") { stage.stage(0, stream) }
            check(stream.actual == ScreenshotPngStage.FILE_BYTES && stream.closed)
            check(dir.listFiles()!!.isEmpty()); owned.remove(dir)
        }
        val dir = owned.create(); val budget = ScreenshotPngStage(dir)
        repeat(3) { i ->
            val stream = SyntheticStream(Long.MAX_VALUE)
            fails("SafFileLimit") { budget.stage(i, stream) }
            check(stream.actual == ScreenshotPngStage.FILE_BYTES)
        }
        val fourth = SyntheticStream(1000)
        fails("SafBatchLimit") { budget.stage(3, fourth) }
        check(fourth.actual == 0L && fourth.closed)
        check(budget.bytesRead == ScreenshotPngStage.BATCH_BYTES)
        owned.remove(dir)

        val badDir = owned.create(); val bad = ScreenshotPngStage(badDir)
        val nonPng = SyntheticStream(Long.MAX_VALUE, ByteArray(33))
        fails("SafPng") { bad.stage(0, nonPng) }; check(nonPng.actual == 33L)
        val enormous = SyntheticStream(Long.MAX_VALUE, header(4097, 100))
        fails("SafPixelLimit") { bad.stage(1, enormous) }; check(enormous.actual == 33L)
        check(bad.bytesRead == 66L); owned.remove(badDir)

        val pixelDir = owned.create(); val pixels = ScreenshotPngStage(pixelDir)
        pixels.stage(0, ByteArrayInputStream(header(4096, 3072)))
        pixels.stage(1, ByteArrayInputStream(header(4096, 3072)))
        val extra = SyntheticStream(Long.MAX_VALUE)
        fails("SafPixelLimit") { pixels.stage(2, extra) }; check(extra.actual == 33L)
        check(pixels.pixels == ScreenshotPngStage.BATCH_PIXELS); owned.remove(pixelDir)

        val cancelDir = owned.create(); val cancelled = ScreenshotPngStage(cancelDir)
        val stream = SyntheticStream(Long.MAX_VALUE)
        stream.afterRead = { if (stream.actual > 33) cancelled.stop() }
        fails("SafCancelled") { cancelled.stage(0, stream) }
        check(stream.closed && stream.actual <= 33 + 32 * 1024)
        check(cancelDir.listFiles()!!.isEmpty()); owned.remove(cancelDir)

        val unrelated = File(cache, "file_picker/other.png").apply { parentFile.mkdirs(); writeText("sentinel") }
        val unknown = File(cache, "wp17-screenshot-import/keep.txt").apply { writeText("unrelated") }
        val leftover = owned.create().apply { File(this, "image-0.png").writeBytes(bytes) }
        owned.purge(); check(!leftover.exists()); check(unrelated.readText() == "sentinel"); check(unknown.exists())
        fails("CleanupFailed") { owned.remove(cache) }; check(cache.exists())
        println("WP17-I3b JVM stream/limit/cancel/owned-cleanup checks passed")
    } finally { cache.deleteRecursively() }
}
