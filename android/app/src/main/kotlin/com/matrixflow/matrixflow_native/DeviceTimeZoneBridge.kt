package com.matrixflow.matrixflow_native

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

/**
 * Reports the device IANA time zone to Dart and forwards system zone changes.
 *
 * The identity comes from [TimeZone.getDefault], which Android already names as
 * an IANA id; no current UTC offset or locale is consulted here, and no guess
 * is made when the platform cannot answer.
 */
class DeviceTimeZoneBridge(
    private val context: Context,
    private val channel: MethodChannel,
) {
    private var receiver: BroadcastReceiver? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "systemZone" -> result.success(
                    mapOf("platform" to "android", "identity" to currentZoneId())
                )
                else -> result.notImplemented()
            }
        }
    }

    /** Starts listening for Intent.ACTION_TIMEZONE_CHANGED. */
    fun start() {
        if (receiver != null) return
        val listener = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                channel.invokeMethod("onTimeZoneChanged", null)
            }
        }
        receiver = listener
        val filter = IntentFilter(Intent.ACTION_TIMEZONE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // A protected system broadcast still reaches a non-exported receiver.
            context.registerReceiver(listener, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(listener, filter)
        }
    }

    fun destroy() {
        receiver?.let { listener ->
            runCatching { context.unregisterReceiver(listener) }
        }
        receiver = null
        channel.setMethodCallHandler(null)
    }

    private fun currentZoneId(): String? {
        val id = TimeZone.getDefault()?.id?.trim()
        return if (id.isNullOrEmpty()) null else id
    }
}
