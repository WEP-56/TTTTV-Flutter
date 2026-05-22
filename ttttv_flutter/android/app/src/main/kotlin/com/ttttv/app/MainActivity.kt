package com.ttttv.app

import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val brightnessChannel = "ttttv/screen_brightness"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, brightnessChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "get" -> result.success(readBrightness())
                    "set" -> {
                        val value = (call.arguments as? Number)?.toFloat()
                        if (value == null) {
                            result.error("invalid_argument", "Brightness must be a number.", null)
                            return@setMethodCallHandler
                        }
                        setBrightness(value)
                        result.success(null)
                    }
                    "reset" -> {
                        resetBrightness()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun readBrightness(): Float {
        val windowBrightness = window.attributes.screenBrightness
        if (windowBrightness >= 0f) {
            return windowBrightness.coerceIn(0f, 1f)
        }

        return try {
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS)
                .toFloat()
                .div(255f)
                .coerceIn(0f, 1f)
        } catch (_: Settings.SettingNotFoundException) {
            1f
        }
    }

    private fun setBrightness(value: Float) {
        val attrs = window.attributes
        attrs.screenBrightness = value.coerceIn(0f, 1f)
        window.attributes = attrs
    }

    private fun resetBrightness() {
        val attrs = window.attributes
        attrs.screenBrightness = -1f
        window.attributes = attrs
    }
}
