package com.compoise.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * In-app update: device ABIs, the "install unknown apps" permission and
 * handing a verified APK from the app's private update folder to the system
 * installer. Only files inside cache/updates are shared.
 */
class AppUpdateBridge(private val activity: Activity, private val channel: MethodChannel) {
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "canInstall" -> result.success(
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                        activity.packageManager.canRequestPackageInstalls()
                )
                "openInstallSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            activity.startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:" + activity.packageName)
                                )
                            )
                        } catch (_: Exception) {
                        }
                    }
                    result.success(null)
                }
                "install" -> result.success(install(call.argument<String>("path")))
                else -> result.notImplemented()
            }
        }
    }

    private fun install(path: String?): Boolean {
        if (path == null) return false
        return try {
            val folder = File(activity.cacheDir, "updates").canonicalFile
            val file = File(path).canonicalFile
            if (file.parentFile != folder || !file.isFile) return false
            val uri = FileProvider.getUriForFile(
                activity, activity.packageName + ".updates", file
            )
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    fun destroy() {
        channel.setMethodCallHandler(null)
    }
}
