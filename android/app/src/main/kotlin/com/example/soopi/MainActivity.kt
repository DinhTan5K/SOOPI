package com.example.soopi

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
