package com.matrixflow.matrixflow_native

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent

class MainActivity : FlutterActivity() {
    private var screenshots: ScreenshotSafBridge? = null
    private var timeZone: DeviceTimeZoneBridge? = null
    private var ocrAssets: OcrAssetsBridge? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        screenshots = ScreenshotSafBridge(this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.matrixflow/screenshot_import"))
        timeZone = DeviceTimeZoneBridge(this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "matrixflow/device_time_zone"))
        timeZone?.start()
        ocrAssets = OcrAssetsBridge(this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.matrixflow/ocr_assets"))
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (screenshots?.onActivityResult(requestCode, resultCode, data) != true) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
    override fun onDestroy() {
        screenshots?.destroy()
        screenshots = null
        timeZone?.destroy()
        timeZone = null
        ocrAssets?.destroy()
        ocrAssets = null
        super.onDestroy()
    }
}
