package com.klambocore.klambo

import android.app.AlarmManager
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
    private var backgroundChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        backgroundChannel = channel
        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        ContextCompat.startForegroundService(
                            this,
                            Intent(this, AlertConnectionService::class.java)
                                .setAction(AlertConnectionService.ACTION_START),
                        )
                        // Si un appel est déjà en attente (FSI / notif), pousser Flutter.
                        flushPendingCallToFlutter()
                        result.success(null)
                    }
                    "stop" -> {
                        // Flag avant stopService : sinon onDestroy relancerait le FGS.
                        getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                            .edit()
                            .putBoolean("flutter.klambo_bg_wanted", false)
                            .apply()
                        stopService(
                            Intent(this, AlertConnectionService::class.java)
                                .setAction(AlertConnectionService.ACTION_STOP),
                        )
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
                    "prepareIncomingCalls" -> {
                        result.success(ensureBackgroundPrivileges())
                    }
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
        // Relayer un appel déjà capturé avant que le channel soit prêt.
        flushPendingCallToFlutter()
    }

    /**
     * Au cold start / après MAJ, ne pas enchaîner les écrans Réglages :
     * ça fait croire que Klambo s'est fermé. Au plus 1 prompt / 12 h.
     */
    private fun ensureBackgroundPrivileges(): Boolean {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val lastPrompt = prefs.getLong(PRIVILEGE_PROMPT_AT, 0L)
        val now = System.currentTimeMillis()
        if (now - lastPrompt < 12L * 60L * 60L * 1000L) {
            return isFullyPrivileged()
        }

        try {
            val pm = getSystemService(PowerManager::class.java)
            if (pm != null && !pm.isIgnoringBatteryOptimizations(packageName)) {
                val ok = openSettingOnce(
                    prefs,
                    now,
                    Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                    },
                )
                if (ok) return false
            }
        } catch (_: Exception) {
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val am = getSystemService(AlarmManager::class.java)
                if (am != null && !am.canScheduleExactAlarms()) {
                    val ok = openSettingOnce(
                        prefs,
                        now,
                        Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                            data = Uri.parse("package:$packageName")
                        },
                    )
                    if (ok) return false
                }
            } catch (_: Exception) {
            }
        }
        // Overlay / FSI : pas d'auto-ouverture au lancement (trop intrusif).
        return isFullyPrivileged()
    }

    private fun isFullyPrivileged(): Boolean {
        if (!isBatteryExempt()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val am = getSystemService(AlarmManager::class.java)
                if (am != null && !am.canScheduleExactAlarms()) return false
            } catch (_: Exception) {
            }
        }
        return true
    }

    private fun isBatteryExempt(): Boolean {
        return try {
            getSystemService(PowerManager::class.java)
                ?.isIgnoringBatteryOptimizations(packageName) == true
        } catch (_: Exception) {
            false
        }
    }

    private fun openSettingOnce(
        prefs: android.content.SharedPreferences,
        now: Long,
        intent: Intent,
    ): Boolean {
        if (!openSetting(intent)) return false
        prefs.edit().putLong(PRIVILEGE_PROMPT_AT, now).apply()
        return true
    }

    private fun openSetting(intent: Intent): Boolean {
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
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

    /** Affiche l'UI d'appel par-dessus le verrou + allume l'écran. */
    private fun setCallHoldsScreen(hold: Boolean) {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(hold)
            setTurnScreenOn(hold)
        } else if (hold) {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            )
        } else {
            @Suppress("DEPRECATION")
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
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

    override fun onDestroy() {
        stopSystemRing()
        backgroundChannel = null
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
        flushPendingCallToFlutter()
    }

    override fun onPause() {
        AppVisibility.inForeground = false
        super.onPause()
    }

    private fun captureCall(intent: Intent?) {
        val raw = intent?.getStringExtra(AlertConnectionService.EXTRA_CALL) ?: return
        pendingCall = raw
        autoAccept = intent.getBooleanExtra(AlertConnectionService.EXTRA_ACCEPT, false)
        // Ouvre immédiatement la fenêtre d'appel (écran verrouillé inclus).
        setCallHoldsScreen(true)
        flushPendingCallToFlutter()
    }

    /** Pousse l'offre native vers Flutter pour ouvrir CallScreen tout de suite. */
    private fun flushPendingCallToFlutter() {
        val raw = pendingCall ?: return
        val channel = backgroundChannel ?: return
        try {
            channel.invokeMethod(
                "incomingCall",
                mapOf(
                    "event" to raw,
                    "autoAccept" to autoAccept,
                ),
            )
        } catch (_: Exception) {
        }
    }

    companion object {
        private const val CHANNEL = "klambo/background"
        private const val LOCK_CHANNEL = "com.klambocore.klambo/lock_screen"
        private const val PRIVILEGE_PROMPT_AT = "flutter.klambo_privilege_prompt_at"
    }
}
