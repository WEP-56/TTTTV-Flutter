package com.ttttv.app

import android.provider.Settings
import android.app.PictureInPictureParams
import android.app.PendingIntent
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Rational
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val brightnessChannel = "ttttv/screen_brightness"
    private var mediaChannel: MethodChannel? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var playing = false
    private val pipAction = "com.ttttv.app.PIP_TOGGLE"
    private var receiverRegistered = false
    private val pipReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == pipAction) mediaChannel?.invokeMethod("togglePlayback", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ttttv/media")
        mediaChannel?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "supportsPip" -> result.success(supportsPip())
                    "enterPip" -> {
                        if (supportsPip() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            result.success(enterPictureInPictureMode(pipParams()))
                        } else result.success(false)
                    }
                    "setPlaying" -> {
                        playing = call.arguments == true
                        if (supportsPip() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            setPictureInPictureParams(pipParams())
                        }
                        result.success(null)
                    }
                    "multicast" -> {
                        if (call.arguments == true) {
                            if (multicastLock == null) {
                                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                                multicastLock = wifi.createMulticastLock("ttttv-dlna").apply { setReferenceCounted(true) }
                            }
                            multicastLock?.acquire()
                        } else if (multicastLock?.isHeld == true) multicastLock?.release()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("media_error", error.message, null)
            }
        }
        if (!receiverRegistered) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(pipReceiver, IntentFilter(pipAction), Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(pipReceiver, IntentFilter(pipAction))
            }
            receiverRegistered = true
        }
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

    private fun supportsPip(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
        packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    @android.annotation.TargetApi(Build.VERSION_CODES.O)
    private fun pipParams(): PictureInPictureParams {
        val pending = PendingIntent.getBroadcast(this, 0,
            Intent(pipAction).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val label = if (playing) "暂停" else "播放"
        val icon = if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        return PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .setActions(listOf(RemoteAction(Icon.createWithResource(this, icon), label, label, pending)))
            .build()
    }

    override fun onPictureInPictureModeChanged(inPip: Boolean, config: Configuration) {
        super.onPictureInPictureModeChanged(inPip, config)
        mediaChannel?.invokeMethod("pipChanged", inPip)
    }

    override fun onStop() {
        super.onStop()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode) {
            mediaChannel?.invokeMethod("pipClosed", null)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        mediaChannel?.setMethodCallHandler(null)
        mediaChannel = null
        if (multicastLock?.isHeld == true) multicastLock?.release()
        if (receiverRegistered) {
            unregisterReceiver(pipReceiver)
            receiverRegistered = false
        }
        super.cleanUpFlutterEngine(flutterEngine)
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
