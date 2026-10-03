package com.klambocore.klambo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.net.URLEncoder
import java.util.concurrent.TimeUnit
import kotlin.math.min

/**
 * Garde une connexion messagerie ouverte quand l'écran est verrouillé
 * ou quand l'activité Flutter a été quittée. Le son est celui du téléphone.
 */
class AlertConnectionService : Service() {
    private val client = OkHttpClient.Builder()
        .pingInterval(20, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()
    private var socket: WebSocket? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var stopped = false
    private var attempt = 0
    private var generation = 0
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var reconnect: Runnable? = null
    private val messageNotifIds = HashMap<String, Int>()
    private var messageSeq = 3000

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        stopped = false
        ensureChannels()
        val ongoing = ongoingNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                ONGOING_ID,
                ongoing,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING,
            )
        } else {
            startForeground(ONGOING_ID, ongoing)
        }
        acquireWakeLock()
        connect()
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (!stopped) {
            val restart = Intent(applicationContext, AlertConnectionService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                applicationContext.startForegroundService(restart)
            } else {
                applicationContext.startService(restart)
            }
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        stopped = true
        reconnect?.let { mainHandler.removeCallbacks(it) }
        socket?.close(1000, "stop")
        socket = null
        client.dispatcher.executorService.shutdown()
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(PowerManager::class.java)
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "klambo:alerts").apply {
            setReferenceCounted(false)
            acquire(8 * 60 * 60 * 1000L)
        }
    }

    private fun prefs() =
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    private fun connect() {
        if (stopped) return
        val token = prefs().getString("flutter.klambo_auth_token", null)
        if (token.isNullOrBlank()) {
            stopSelf()
            return
        }
        val base = prefs().getString("flutter.klambo_api_base_url", null)
            ?.trim()
            ?.ifBlank { null }
            ?: "https://klambocore.com"
        val url = wsUrl(base, token)
        val gen = ++generation
        socket?.cancel()
        val request = Request.Builder().url(url).build()
        socket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                if (gen == generation) attempt = 0
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                if (gen == generation) handleMessage(text)
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(code, reason)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                if (gen == generation) scheduleReconnect()
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                if (gen == generation) scheduleReconnect()
            }
        })
    }

    private fun scheduleReconnect() {
        if (stopped) return
        reconnect?.let { mainHandler.removeCallbacks(it) }
        val delay = min(30, listOf(2, 3, 5, 8, 13, 21, 30)[min(attempt, 6)]) * 1000L
        attempt += 1
        val task = Runnable { connect() }
        reconnect = task
        mainHandler.postDelayed(task, delay)
    }

    private fun handleMessage(text: String) {
        val event = try {
            JSONObject(text)
        } catch (_: Exception) {
            return
        }
        if (event.optString("type") == "ping") return
        if (flutterStillAlive()) return
        val type = event.optString("type")
        val me = myUserId()
        when {
            type == "message.created" -> showMessage(event, me)
            type == "call.offer" && event.optString("toUserId") == me -> showCall(event)
        }
    }

    /** L'interface Flutter notifie elle-même tant que son horloge est récente. */
    private fun flutterStillAlive(): Boolean {
        val stored = prefs()
        val beat = try {
            stored.getLong("flutter.klambo_ui_heartbeat", 0L)
        } catch (_: ClassCastException) {
            stored.getInt("flutter.klambo_ui_heartbeat", 0).toLong()
        }
        if (beat <= 0L) return false
        return System.currentTimeMillis() - beat < 8_000L
    }

    private fun myUserId(): String? {
        val raw = prefs().getString("flutter.klambo_me_snapshot", null) ?: return null
        return try {
            val root = JSONObject(raw)
            val user = root.optJSONObject("user")
                ?: root.optJSONObject("me")?.optJSONObject("user")
            user?.optString("id")?.takeIf { it.isNotBlank() }
        } catch (_: Exception) {
            null
        }
    }

    private fun soundsOn() = prefs().getBoolean("flutter.klambo_alert_sounds", true)

    private fun showMessage(event: JSONObject, me: String?) {
        if (!prefs().getBoolean("flutter.klambo_alert_message_notif", true)) return
        val sender = event.optString("senderId").ifBlank {
            event.optJSONObject("payload")?.optString("senderId").orEmpty()
        }
        if (sender.isNotBlank() && sender == me) return
        val payload = event.optJSONObject("payload")
        val title = event.optString("senderName").ifBlank {
            payload?.optString("senderName").orEmpty()
        }.ifBlank { "Klambocore" }
        val body = event.optString("bodyPreview").ifBlank {
            event.optString("body").ifBlank {
                payload?.optString("body").orEmpty()
            }
        }.ifBlank { "Nouveau message" }
        val thread = event.optString("conversationId").ifBlank { title }
        val manager = getSystemService(NotificationManager::class.java)
        messageNotifIds[thread]?.let { manager.cancel(it) }
        val id = 3000 + (messageSeq++ % 40000)
        messageNotifIds[thread] = id
        val image = event.optString("senderImage").ifBlank {
            payload?.optString("senderImage").orEmpty()
        }
        notify(
            id,
            MESSAGE_CHANNEL,
            title,
            body,
            soundsOn(),
            call = false,
            avatar = avatarBitmap(image),
        )
    }

    private fun showCall(event: JSONObject) {
        if (!prefs().getBoolean("flutter.klambo_alert_call_notif", true)) return
        val payload = event.optJSONObject("payload")
        val title = payload?.optString("callerName").orEmpty().ifBlank { "Klambocore" }
        val kind = payload?.optString("kind").orEmpty()
        val body = if (kind.equals("VIDEO", true)) "Appel vidéo entrant" else "Appel audio entrant"
        notify(900001, CALL_CHANNEL, title, body, soundsOn(), call = true)
    }

    private fun notify(
        id: Int,
        channel: String,
        title: String,
        body: String,
        sound: Boolean,
        call: Boolean,
        avatar: Bitmap? = null,
    ) {
        val launch = PendingIntent.getActivity(
            this,
            id,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(launch)
            .setCategory(if (call) Notification.CATEGORY_CALL else Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(false)
        if (avatar != null) builder.setLargeIcon(avatar)
        if (sound) {
            val uri = if (call) {
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            } else {
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            }
            builder.setSound(uri)
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            builder.setPriority(Notification.PRIORITY_HIGH)
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(id, builder.build())
    }

    private fun ongoingNotification(): Notification {
        val launch = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, PRESENCE_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle("Klambocore")
            .setContentText("Alertes actives")
            .setOngoing(true)
            .setContentIntent(launch)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_SECRET)
            .build()
    }

    private fun resolveImage(src: String?): String? {
        val trimmed = src?.trim().orEmpty()
        if (trimmed.isEmpty() || trimmed.startsWith("data:")) return null
        if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) return trimmed
        val stored = prefs().getString("flutter.klambo_api_base_url", null)
            ?.trim()
            ?.trimEnd('/')
            ?.ifBlank { null }
        val base = stored ?: "https://klambocore.com"
        return if (trimmed.startsWith("/")) "$base$trimmed" else "$base/uploads/$trimmed"
    }

    private fun avatarBitmap(raw: String?): Bitmap? {
        val url = resolveImage(raw) ?: return null
        return try {
            val response = client.newCall(Request.Builder().url(url).get().build()).execute()
            response.use { res ->
                if (!res.isSuccessful) return null
                val bytes = res.body?.bytes() ?: return null
                if (bytes.size < 32 || bytes.size > 2_000_000) return null
                val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
                Bitmap.createScaledBitmap(decoded, 192, 192, true)
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val messageSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val ringSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        manager.createNotificationChannel(
            NotificationChannel(MESSAGE_CHANNEL, "Messages Klambocore", NotificationManager.IMPORTANCE_MAX).apply {
                description = "Nouveaux messages, même écran verrouillé"
                setSound(messageSound, attrs)
                enableVibration(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(CALL_CHANNEL, "Appels Klambocore", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Appels entrants"
                setSound(ringSound, AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build())
                enableVibration(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(PRESENCE_CHANNEL, "Connexion Klambocore", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Maintient les alertes en arrière-plan"
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
            },
        )
    }

    companion object {
        private const val ONGOING_ID = 42
        private const val MESSAGE_CHANNEL = "klambo_messages_bg_v2"
        private const val CALL_CHANNEL = "klambo_calls_bg_v1"
        private const val PRESENCE_CHANNEL = "klambo_presence_v1"

        fun wsUrl(baseRaw: String, token: String): String {
            val cleaned = baseRaw.trim().trimEnd('/')
            val withScheme = if (cleaned.contains("://")) cleaned else "https://$cleaned"
            val uri = Uri.parse(withScheme)
            val secure = uri.scheme == "https"
            val scheme = if (secure) "wss" else "ws"
            val port = when (uri.port) {
                3000, 3001 -> 3010
                else -> uri.port
            }
            val host = uri.host ?: "klambocore.com"
            val authority = if (port == -1 || port == 80 || port == 443) host else "$host:$port"
            val encoded = URLEncoder.encode(token, "UTF-8")
            return "$scheme://$authority/api/mobile/ws?token=$encoded"
        }
    }
}
