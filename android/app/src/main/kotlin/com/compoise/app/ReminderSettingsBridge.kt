package com.compoise.app

import android.Manifest
import android.app.AlarmManager
import androidx.core.app.NotificationManagerCompat
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

/** Permission prompts and settings routes; no foreground service or keep-alive loop. */
class ReminderSettingsBridge(
    private val activity: FlutterActivity,
    private val channel: MethodChannel,
) {
    companion object {
        private const val NOTIFICATION_REQUEST = 17431
        private const val SETTINGS_REQUEST = 17432
    }
    private var pending: MethodChannel.Result? = null
    private val appUri get() = Uri.parse("package:${activity.packageName}")

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(mapOf(
                    "notifications" to notificationsEnabled(),
                    "exactAlarms" to exactAlarmsEnabled(),
                    "background" to backgroundEnabled(),
                    "autoStartAvailable" to autoStartIntents().any(::canOpen),
                    "autoStart" to autoStartEnabled(),
                ))
                "open" -> {
                    if (pending != null) {
                        result.error("busy", "A settings request is already open", null)
                    } else {
                        open(call.argument<String>("setting"), result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun notificationsEnabled(): Boolean =
        NotificationManagerCompat.from(activity).areNotificationsEnabled()

    private fun exactAlarmsEnabled(): Boolean =
        Build.VERSION.SDK_INT < 31 ||
            activity.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()

    private fun backgroundEnabled(): Boolean =
        Build.VERSION.SDK_INT < 23 || activity.getSystemService(PowerManager::class.java)
            .isIgnoringBatteryOptimizations(activity.packageName)

    // MIUI OP_AUTO_START is 10008: MODE_ALLOWED = 0, MODE_IGNORED = 1.
    // Some HyperOS versions do not expose AppOpsUtils.getApplicationAutoStart; read
    // the underlying operation for our own UID instead, without API bypasses.
    // Other manufacturers and inaccessible/unknown modes remain unknown.
    private fun autoStartEnabled(): Boolean? {
        if (Build.MANUFACTURER.lowercase() !in listOf("xiaomi", "redmi", "poco")) return null
        return try {
            val manager = activity.getSystemService(Context.APP_OPS_SERVICE)
            val method = manager.javaClass.getMethod(
                "checkOpNoThrow", Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType, String::class.java
            )
            when (method.invoke(manager, 10008, android.os.Process.myUid(), activity.packageName) as? Int) {
                0 -> true
                1 -> false
                else -> null
            }
        } catch (_: ReflectiveOperationException) {
            null
        } catch (_: RuntimeException) {
            null
        } catch (_: LinkageError) {
            null
        }
    }

    private fun notificationSettings(): Intent = if (Build.VERSION.SDK_INT >= 26)
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
        else appDetails()

    private fun appDetails() = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, appUri)

    private fun open(setting: String?, result: MethodChannel.Result) {
        if (setting == "notifications" && Build.VERSION.SDK_INT >= 33 && !notificationsEnabled()) {
            pending = result
            try {
                activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
            } catch (_: RuntimeException) {
                pending = null
                result.success(false)
            }
            return
        }
        val intents = when (setting) {
            "notifications", "notificationSettings" -> listOf(notificationSettings(), appDetails())
            "exactAlarms" -> if (Build.VERSION.SDK_INT >= 31) listOf(
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, appUri), appDetails()
            ) else emptyList()
            "background" -> if (Build.VERSION.SDK_INT >= 23) listOf(
                Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, appUri),
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS), appDetails()
            ) else emptyList()
            "autoStart" -> autoStartIntents() + appDetails()
            else -> emptyList()
        }
        for (intent in intents) {
            if (!canOpen(intent)) continue
            pending = result
            try {
                activity.startActivityForResult(intent, SETTINGS_REQUEST)
                return
            } catch (_: RuntimeException) {
                pending = null
            }
        }
        result.success(false)
    }

    private fun canOpen(intent: Intent): Boolean {
        val info = activity.packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
            ?.activityInfo ?: return false
        val allowed = info.permission == null ||
            activity.packageManager.checkPermission(info.permission, activity.packageName) == PackageManager.PERMISSION_GRANTED
        return info.exported && allowed
    }

    // OEM routes are probed before use. Missing or protected activities fall
    // back to the system's app settings. Status is read independently above.
    private fun autoStartIntents(): List<Intent> {
        val components = when (Build.MANUFACTURER.lowercase()) {
            "xiaomi", "redmi", "poco" -> listOf(
                "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity"
            )
            "huawei", "honor" -> listOf(
                "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                "com.huawei.systemmanager" to "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity",
                "com.hihonor.systemmanager" to "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
            )
            "oppo", "realme", "oneplus" -> listOf(
                "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
                "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
                "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
                "com.oneplus.security" to "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"
            )
            "vivo", "iqoo" -> listOf(
                "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager"
            )
            else -> emptyList()
        }
        return components.map { (pkg, name) ->
            Intent().setComponent(ComponentName(pkg, name))
                .putExtra("package_name", activity.packageName)
        }
    }

    fun onActivityResult(requestCode: Int): Boolean {
        if (requestCode != SETTINGS_REQUEST) return false
        val result = pending
        pending = null
        result?.success(true)
        return true
    }

    fun onRequestPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != NOTIFICATION_REQUEST) return false
        val result = pending
        pending = null
        // The prompt was opened successfully; status reports grant or denial.
        result?.success(true)
        return true
    }

    fun destroy() {
        channel.setMethodCallHandler(null)
        val result = pending
        pending = null
        result?.error("closed", "The activity closed", null)
    }
}
