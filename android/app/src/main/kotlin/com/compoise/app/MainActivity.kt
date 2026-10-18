package com.compoise.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent

class MainActivity : FlutterActivity() {
    private var quickCapture: QuickCaptureBridge? = null
    private var screenshots: ScreenshotSafBridge? = null
    private var timeZone: DeviceTimeZoneBridge? = null
    private var ocrAssets: OcrAssetsBridge? = null
    private var reminderSettings: ReminderSettingsBridge? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        quickCapture = QuickCaptureBridge(MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "compoise/quick_capture"))
        quickCapture?.accept(intent)
        screenshots = ScreenshotSafBridge(this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.compoise/screenshot_import"))
        timeZone = DeviceTimeZoneBridge(this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "compoise/device_time_zone"))
        timeZone?.start()
        ocrAssets = OcrAssetsBridge(this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.compoise/ocr_assets"))
        reminderSettings = ReminderSettingsBridge(this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "compoise/reminder_settings"))
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (reminderSettings?.onActivityResult(requestCode) != true &&
            screenshots?.onActivityResult(requestCode, resultCode, data) != true) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (reminderSettings?.onRequestPermissionsResult(requestCode) != true) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }
    override fun onDestroy() {
        quickCapture?.destroy()
        quickCapture = null
        screenshots?.destroy()
        screenshots = null
        timeZone?.destroy()
        timeZone = null
        ocrAssets?.destroy()
        ocrAssets = null
        reminderSettings?.destroy()
        reminderSettings = null
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        quickCapture?.accept(intent)
    }
}
