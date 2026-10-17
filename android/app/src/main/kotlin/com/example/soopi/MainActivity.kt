package com.example.soopi

import android.media.Ringtone
import android.media.RingtoneManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.imagepicker.ImagePickerPlugin
import io.flutter.plugins.flutter_plugin_android_lifecycle.FlutterAndroidLifecyclePlugin

class MainActivity : FlutterActivity() {
    private var orderAlert: Ringtone? = null

    override fun onStop() {
        orderAlert?.stop()
        super.onStop()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Ensure gallery support even when a failed desktop plugin setup leaves
        // Flutter's generated Android registrant incomplete.
        if (!flutterEngine.plugins.has(FlutterAndroidLifecyclePlugin::class.java)) {
            flutterEngine.plugins.add(FlutterAndroidLifecyclePlugin())
        }
        if (!flutterEngine.plugins.has(ImagePickerPlugin::class.java)) {
            flutterEngine.plugins.add(ImagePickerPlugin())
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "soopi/order_alert")
            .setMethodCallHandler { call, result ->
                if (call.method == "play") {
                    try {
                        orderAlert?.stop()
                        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                        orderAlert = RingtoneManager.getRingtone(this, uri)
                        orderAlert?.play()
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("AUDIO_FAILED", "Could not play notification sound", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
        val preferences = getSharedPreferences("soopi_merchant", MODE_PRIVATE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "soopi/merchant_storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "load" -> result.success(preferences.getString("data", null))
                    "save" -> {
                        val data = call.arguments as? String
                        if (data == null) {
                            result.error("INVALID_DATA", "Expected JSON data", null)
                        } else if (preferences.edit().putString("data", data).commit()) {
                            result.success(null)
                        } else {
                            result.error("SAVE_FAILED", "Could not save merchant data", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
