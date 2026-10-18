package com.compoise.app

import android.content.Intent
import io.flutter.plugin.common.MethodChannel

/** Text is delivered to Flutter once, where it remains a reviewable draft. */
class QuickCaptureBridge(private val channel: MethodChannel) {
    private val pending = mutableListOf<Map<String, String>>()

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "takePending") {
                val batch = pending.toList()
                pending.clear()
                result.success(batch)
            } else result.notImplemented()
        }
    }

    fun accept(intent: Intent?) {
        val request = when {
            intent?.action == Intent.ACTION_SEND && intent.type == "text/plain" -> {
                val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() ?: return
                if (text.isBlank()) return
                mapOf("action" to "share", "text" to text)
            }
            intent?.action == "com.compoise.app.QUICK_ADD" -> mapOf("action" to "add")
            intent?.action == "com.compoise.app.TODAY" -> mapOf("action" to "today")
            else -> return
        }
        pending.add(request)
        intent?.action = Intent.ACTION_MAIN
        intent?.removeExtra(Intent.EXTRA_TEXT)
        channel.invokeMethod("pendingChanged", null)
    }

    fun destroy() { channel.setMethodCallHandler(null) }
}
