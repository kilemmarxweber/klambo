package com.klambocore.klambo

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingCall: String? = null
    private var autoAccept = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        ContextCompat.startForegroundService(
                            this,
                            Intent(this, AlertConnectionService::class.java),
                        )
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, AlertConnectionService::class.java))
                        result.success(null)
                    }
                    "stopRing" -> {
                        ContextCompat.startForegroundService(
                            this,
                            Intent(this, AlertConnectionService::class.java)
                                .setAction(AlertConnectionService.ACTION_STOP_RING),
                        )
                        result.success(null)
                    }
                    "callOngoing" -> {
                        val name = call.argument<String>("name") ?: "Klambo"
                        val video = call.argument<Boolean>("video") ?: false
                        ContextCompat.startForegroundService(
                            this,
                            Intent(this, AlertConnectionService::class.java)
                                .setAction(AlertConnectionService.ACTION_ONGOING)
                                .putExtra(AlertConnectionService.EXTRA_NAME, name)
                                .putExtra(AlertConnectionService.EXTRA_VIDEO, video),
                        )
                        result.success(null)
                    }
                    "callIdle" -> {
                        ContextCompat.startForegroundService(
                            this,
                            Intent(this, AlertConnectionService::class.java)
                                .setAction(AlertConnectionService.ACTION_IDLE),
                        )
                        result.success(null)
                    }
                    "takePendingCall" -> {
                        val raw = pendingCall
                        val accept = autoAccept
                        pendingCall = null
                        autoAccept = false
                        if (raw.isNullOrBlank()) {
                            result.success(null)
                        } else {
                            result.success(
                                mapOf(
                                    "event" to raw,
                                    "autoAccept" to accept,
                                ),
                            )
                        }
                    }
                    "pushToken" -> result.success(null)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCK_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "setLockScreenVisible") {
                    val visible = call.argument<Boolean>("visible") == true
                    setCallHoldsScreen(visible)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    /** Écran allumé seulement pendant un appel qui passe. Sinon, verrouillage normal. */
    private fun setCallHoldsScreen(hold: Boolean) {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(hold)
            setTurnScreenOn(hold)
        } else if (hold) {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        } else {
            @Suppress("DEPRECATION")
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
        if (hold) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureCall(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureCall(intent)
    }

    override fun onResume() {
        super.onResume()
        AppVisibility.inForeground = true
    }

    override fun onPause() {
        AppVisibility.inForeground = false
        super.onPause()
    }

    private fun captureCall(intent: Intent?) {
        val raw = intent?.getStringExtra(AlertConnectionService.EXTRA_CALL) ?: return
        pendingCall = raw
        autoAccept = intent.getBooleanExtra(AlertConnectionService.EXTRA_ACCEPT, false)
    }

    companion object {
        private const val CHANNEL = "klambo/background"
        private const val LOCK_CHANNEL = "com.klambocore.klambo/lock_screen"
    }
}
