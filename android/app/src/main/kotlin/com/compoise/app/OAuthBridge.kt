package com.compoise.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodChannel

/**
 * Browser sign-in for cloud sync: opens the sign-in page in the default
 * browser and hands the com.compoise.app://oauth redirect back to Flutter.
 * Only the latest redirect is kept; Flutter matches it to its attempt.
 */
class OAuthBridge(private val activity: Activity, private val channel: MethodChannel) {
    private var pending: String? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "open" -> {
                    val url = call.argument<String>("url")
                    if (url == null || !url.startsWith("https://")) {
                        result.success(false)
                    } else {
                        try {
                            activity.startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                    .addCategory(Intent.CATEGORY_BROWSABLE))
                            result.success(true)
                        } catch (e: ActivityNotFoundException) {
                            result.success(false)
                        }
                    }
                }
                "takeRedirect" -> {
                    val value = pending
                    pending = null
                    result.success(value)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** True when [intent] was a sign-in redirect; it is then consumed. */
    fun accept(intent: Intent?): Boolean {
        val data = intent?.data ?: return false
        if (intent.action != Intent.ACTION_VIEW ||
            data.scheme != "com.compoise.app" || data.host != "oauth") return false
        pending = data.toString()
        intent.action = Intent.ACTION_MAIN
        intent.data = null
        channel.invokeMethod("redirect", null)
        return true
    }

    fun destroy() { channel.setMethodCallHandler(null) }
}
