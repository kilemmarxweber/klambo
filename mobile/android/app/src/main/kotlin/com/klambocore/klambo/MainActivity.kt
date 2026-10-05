package com.klambocore.klambo

import android.app.NotificationManager
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingCall: String? = null
    private var autoAccept = false
    private var systemRing: MediaPlayer? = null
    private var callWake: PowerManager.WakeLock? = null

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
                        stopSystemRing()
                        ContextCompat.startForegroundService(
                            this,
                            Intent(this, AlertConnectionService::class.java)
                                .setAction(AlertConnectionService.ACTION_STOP_RING),
                        )
                        result.success(null)
                    }
                    "startSystemRing" -> {
                        startSystemRing()
                        result.success(null)
                    }
                    "stopSystemRing" -> {
                        stopSystemRing()
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
                        var raw = pendingCall
                        var accept = autoAccept
                        pendingCall = null
                        autoAccept = false
                        if (raw.isNullOrBlank()) {
                            val stored = getSharedPreferences(
                                "FlutterSharedPreferences",
                                MODE_PRIVATE,
                            )
                            raw = stored.getString("flutter.klambo_pending_call", null)
                            if (!raw.isNullOrBlank()) {
                                stored.edit().remove("flutter.klambo_pending_call").apply()
                            }
                        }
                        if (raw.isNullOrBlank()) {
                            result.success(null)
                        } else {
                            setCallHoldsScreen(true)
                            result.success(
                                mapOf(
                                    "event" to raw,
                                    "autoAccept" to accept,
                                ),
                            )
                        }
                    }
                    "pushToken" -> result.success(null)
                    "prepareIncomingCalls" -> result.success(prepareIncomingCalls())
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

    /** Sonnerie par défaut du téléphone (réglages Android), en boucle. */
    private fun startSystemRing() {
        stopSystemRing()
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: RingtoneManager.getActualDefaultRingtoneUri(
                applicationContext,
                RingtoneManager.TYPE_RINGTONE,
            )
            ?: return
        val player = MediaPlayer()
        try {
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            player.setDataSource(applicationContext, uri)
            player.isLooping = true
            player.setOnPreparedListener { ready ->
                if (systemRing === ready) ready.start()
            }
            systemRing = player
            player.prepareAsync()
        } catch (_: Exception) {
            try {
                player.release()
            } catch (_: Exception) {
            }
            systemRing = null
        }
    }

    private fun stopSystemRing() {
        val player = systemRing ?: return
        systemRing = null
        try {
            if (player.isPlaying) player.stop()
        } catch (_: Exception) {
        }
        try {
            player.release()
        } catch (_: Exception) {
        }
    }

    /**
     * Page d'appel par-dessus le verrouillage, pour décrocher sans déverrouiller.
     * Coupé dès que l'appel est terminé.
     */
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
            wakeForIncomingCall()
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            releaseCallWake()
        }
    }

    @Suppress("DEPRECATION")
    private fun wakeForIncomingCall() {
        val power = getSystemService(PowerManager::class.java)
        val lock = callWake ?: power.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
            "klambo:call-screen",
        ).also { callWake = it }
        if (!lock.isHeld) lock.acquire(60_000L)
    }

    private fun releaseCallWake() {
        val lock = callWake ?: return
        if (lock.isHeld) lock.release()
    }

    /** Une fois : plein écran sur écran verrouillé, sinon exemption batterie. */
    private fun prepareIncomingCalls(): Boolean {
        if (Build.VERSION.SDK_INT >= 34) {
            val manager = getSystemService(NotificationManager::class.java)
            if (!manager.canUseFullScreenIntent()) {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                        data = Uri.parse("package:$packageName")
                    },
                )
                return true
            }
        }
        val power = getSystemService(PowerManager::class.java)
        if (!power.isIgnoringBatteryOptimizations(packageName)) {
            try {
                startActivity(
                    Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                    },
                )
                return true
            } catch (_: Exception) {
            }
        }
        return false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.hasExtra(AlertConnectionService.EXTRA_CALL) == true) {
            setCallHoldsScreen(true)
        }
        captureCall(intent)
    }

    override fun onDestroy() {
        stopSystemRing()
        releaseCallWake()
        super.onDestroy()
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
        setCallHoldsScreen(true)
        pendingCall = raw
        autoAccept = intent.getBooleanExtra(AlertConnectionService.EXTRA_ACCEPT, false)
    }

    companion object {
        private const val CHANNEL = "klambo/background"
        private const val LOCK_CHANNEL = "com.klambocore.klambo/lock_screen"
    }
}
