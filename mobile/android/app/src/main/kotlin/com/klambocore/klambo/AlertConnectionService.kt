package com.klambocore.klambo

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
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
    private var callAudioHeld = false
    private var previousAudioMode = AudioManager.MODE_NORMAL
    private var audioFocusRequest: AudioFocusRequest? = null
    private var stopped = false
    private var attempt = 0
    private var generation = 0
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private var reconnect: Runnable? = null
    private val messageNotifIds = HashMap<String, Int>()
    private var messageSeq = 3000
    private var ringtone: Ringtone? = null
    private var ringTimeout: Runnable? = null
    private var ringingCallId: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        stopped = false
        AppVisibility.serviceRunning = true
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
        when (intent?.action) {
            ACTION_STOP_RING -> {
                stopRing()
                return START_STICKY
            }
            ACTION_DECLINE -> {
                declinePending()
                return START_STICKY
            }
            ACTION_ONGOING -> {
                val name = intent.getStringExtra(EXTRA_NAME) ?: "Klambo"
                val video = intent.getBooleanExtra(EXTRA_VIDEO, false)
                try {
                    startInCallForeground(callOngoingNotification(name), video)
                } catch (error: Exception) {
                    // Un type micro/caméra refusé ne doit pas tuer l'app au décroché.
                    android.util.Log.w("klambo", "in-call foreground", error)
                    try {
                        startMessagingForeground(ongoing)
                    } catch (_: Exception) {
                    }
                }
                return START_STICKY
            }
            ACTION_IDLE -> {
                startMessagingForeground(ongoing)
                return START_STICKY
            }
        }
        acquireWakeLock()
        if (socket == null) connect()
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
        AppVisibility.serviceRunning = false
        reconnect?.let { mainHandler.removeCallbacks(it) }
        ringTimeout?.let { mainHandler.removeCallbacks(it) }
        stopRing()
        socket?.close(1000, "stop")
        socket = null
        client.dispatcher.executorService.shutdown()
        releaseCallAudio()
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }

    /** Micro et CPU restent actifs écran verrouillé, le temps de l'appel. */
    private fun holdCallAudio() {
        acquireWakeLock()
        val am = getSystemService(AudioManager::class.java) ?: return
        if (!callAudioHeld) {
            previousAudioMode = am.mode
            callAudioHeld = true
        }
        am.mode = AudioManager.MODE_IN_COMMUNICATION
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attrs)
                .setAcceptsDelayedFocusGain(true)
                .build()
            audioFocusRequest = request
            am.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(
                null,
                AudioManager.STREAM_VOICE_CALL,
                AudioManager.AUDIOFOCUS_GAIN,
            )
        }
    }

    private fun releaseCallAudio() {
        if (!callAudioHeld) return
        val am = getSystemService(AudioManager::class.java)
        if (am != null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let { am.abandonAudioFocusRequest(it) }
            } else {
                @Suppress("DEPRECATION")
                am.abandonAudioFocus(null)
            }
            am.mode = previousAudioMode
        }
        audioFocusRequest = null
        callAudioHeld = false
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
        val type = event.optString("type")
        if (type == "ping" || type == "pong" || type == "connected") return
        val me = myUserId()
        val callId = event.optString("callId")
        if ((type == "call.hangup" || type == "call.reject" || type == "call.ended") &&
            callId.isNotBlank() && callId == ringingCallId
        ) {
            stopIncoming()
            return
        }
        // L'écran ouvert gère lui-même messages et appels.
        // Écran verrouillé : toujours la page d'appel, même si Flutter est encore là.
        if (AppVisibility.inForeground && flutterStillAlive() && !screenLocked()) return
        when {
            type == "message.created" -> showMessage(event, me)
            type == "call.offer" && event.optString("toUserId") == me -> showCall(event)
        }
    }

    private fun screenLocked(): Boolean {
        val power = getSystemService(PowerManager::class.java)
        val keyguard = getSystemService(KeyguardManager::class.java)
        return !power.isInteractive || keyguard.isKeyguardLocked
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
        val callId = event.optString("callId")
        if (callId.isBlank()) return
        ringingCallId = callId
        prefs().edit().putString(PENDING_CALL_KEY, event.toString()).commit()
        val payload = event.optJSONObject("payload")
        val title = payload?.optString("callerName").orEmpty().ifBlank { "Klambocore" }
        val kind = payload?.optString("kind").orEmpty()
        val body = if (kind.equals("VIDEO", true)) "Appel vidéo entrant" else "Appel audio entrant"
        val image = payload?.optString("callerImage").orEmpty().ifBlank {
            event.optString("callerImage")
        }
        wakeScreen()
        postIncomingCall(title, body, event.toString(), soundsOn(), avatarBitmap(image))
        bringCallToFront(event.toString())
        if (soundsOn()) startRing()
        armRingTimeout()
    }

    private fun wakeScreen() {
        val pm = getSystemService(PowerManager::class.java)
        if (pm.isInteractive) return
        val lock = pm.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                PowerManager.ACQUIRE_CAUSES_WAKEUP or
                PowerManager.ON_AFTER_RELEASE,
            "klambo:incoming-call",
        )
        lock.acquire(12_000L)
    }

    private fun startRing() {
        stopRing()
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val tone = RingtoneManager.getRingtone(applicationContext, uri) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) tone.isLooping = true
        tone.audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        ringtone = tone
        tone.play()
    }

    private fun stopRing() {
        ringTimeout?.let { mainHandler.removeCallbacks(it) }
        ringTimeout = null
        try {
            ringtone?.stop()
        } catch (_: Exception) {
        }
        ringtone = null
    }

    private fun armRingTimeout() {
        ringTimeout?.let { mainHandler.removeCallbacks(it) }
        val task = Runnable {
            if (ringingCallId != null) stopIncoming()
        }
        ringTimeout = task
        mainHandler.postDelayed(task, 45_000L)
    }

    private fun stopIncoming() {
        ringingCallId = null
        prefs().edit().remove(PENDING_CALL_KEY).apply()
        stopRing()
        getSystemService(NotificationManager::class.java).cancel(CALL_NOTIF_ID)
    }

    private fun declinePending() {
        val raw = prefs().getString(PENDING_CALL_KEY, null)
        stopIncoming()
        if (raw.isNullOrBlank()) return
        val event = try {
            JSONObject(raw)
        } catch (_: Exception) {
            return
        }
        val org = event.optString("organizationId")
        val callId = event.optString("callId")
        val peer = event.optString("fromUserId")
        val me = myUserId()
        if (org.isBlank() || callId.isBlank()) return
        socket?.send(
            JSONObject()
                .put("type", "call.reject")
                .put("organizationId", org)
                .put("callId", callId)
                .put("toUserId", peer)
                .put("fromUserId", me ?: "")
                .toString(),
        )
        val token = prefs().getString("flutter.klambo_auth_token", null) ?: return
        val url = apiBase() + "/api/mobile/v1/organizations/$org/calls/$callId/actions"
        val body = """{"action":"reject"}""".toRequestBody("application/json".toMediaType())
        val request = Request.Builder()
            .url(url)
            .addHeader("Authorization", "Bearer $token")
            .post(body)
            .build()
        client.newCall(request).enqueue(object : okhttp3.Callback {
            override fun onFailure(call: okhttp3.Call, e: java.io.IOException) {}
            override fun onResponse(call: okhttp3.Call, response: Response) {
                response.close()
            }
        })
    }

    private fun apiBase(): String {
        val stored = prefs().getString("flutter.klambo_api_base_url", null)
            ?.trim()
            ?.trimEnd('/')
            ?.ifBlank { null }
        return stored ?: "https://klambocore.com"
    }

    private fun incomingIntent(raw: String, accept: Boolean): Intent {
        return Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_CALL, raw)
            putExtra(EXTRA_ACCEPT, accept)
        }
    }

    private fun startMessagingForeground(notification: Notification) {
        releaseCallAudio()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                ONGOING_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING,
            )
        } else {
            startForeground(ONGOING_ID, notification)
        }
    }

    private fun startInCallForeground(notification: Notification, video: Boolean) {
        holdCallAudio()
        if (Build.VERSION.SDK_INT >= 30) {
            var types = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            if (video) {
                types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            }
            if (Build.VERSION.SDK_INT >= 34) {
                types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING
            }
            startForeground(ONGOING_ID, notification, types)
        } else {
            startForeground(ONGOING_ID, notification)
        }
    }

    private fun callOngoingNotification(name: String): Notification {
        val launch = PendingIntent.getActivity(
            this,
            14,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CALL_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.stat_sys_phone_call)
            .setContentTitle(name)
            .setContentText("Appel en cours")
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_CALL)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(launch)
            .build()
    }

    private fun bringCallToFront(raw: String) {
        try {
            startActivity(incomingIntent(raw, accept = false))
        } catch (_: Exception) {
        }
    }

    private fun postIncomingCall(
        title: String,
        body: String,
        raw: String,
        sound: Boolean,
        avatar: Bitmap? = null,
    ) {
        val open = PendingIntent.getActivity(
            this,
            13,
            incomingIntent(raw, accept = false),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val answer = PendingIntent.getActivity(
            this,
            11,
            incomingIntent(raw, accept = true),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val decline = PendingIntent.getService(
            this,
            12,
            Intent(this, AlertConnectionService::class.java).setAction(ACTION_DECLINE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CALL_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(Notification.CATEGORY_CALL)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(open)
            .setFullScreenIntent(open, true)
            .setOnlyAlertOnce(false)
        if (avatar != null) builder.setLargeIcon(avatar)
        if (Build.VERSION.SDK_INT >= 31) {
            val person = Person.Builder().setName(title).setImportant(true)
            if (avatar != null) person.setIcon(Icon.createWithBitmap(avatar))
            val caller = person.build()
            builder.setStyle(Notification.CallStyle.forIncomingCall(caller, decline, answer))
            builder.addPerson(caller)
        } else {
            builder.addAction(0, "Refuser", decline)
            builder.addAction(0, "Décrocher", answer)
        }
        if (sound && Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            builder.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            builder.setPriority(Notification.PRIORITY_MAX)
        }
        getSystemService(NotificationManager::class.java).notify(CALL_NOTIF_ID, builder.build())
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
            .setAutoCancel(true)
            .setContentIntent(launch)
            .setCategory(if (call) Notification.CATEGORY_CALL else Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(false)
        if (avatar != null && !call && Build.VERSION.SDK_INT >= 28) {
            val sender = Person.Builder()
                .setName(title)
                .setIcon(Icon.createWithBitmap(avatar))
                .setImportant(true)
                .build()
            builder.setStyle(
                Notification.MessagingStyle(Person.Builder().setName("Moi").build())
                    .addMessage(body, System.currentTimeMillis(), sender),
            )
            builder.setLargeIcon(avatar)
        } else {
            builder.setStyle(Notification.BigTextStyle().bigText(body))
            if (avatar != null) builder.setLargeIcon(avatar)
        }
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
            .setContentTitle("Klambo")
            .setContentText("Prêt à recevoir les appels")
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
                val circled = circleBitmap(decoded)
                if (circled != decoded && !decoded.isRecycled) decoded.recycle()
                circled
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun circleBitmap(source: Bitmap): Bitmap {
        val size = 192
        val side = min(source.width, source.height)
        val cropped = Bitmap.createBitmap(
            source,
            (source.width - side) / 2,
            (source.height - side) / 2,
            side,
            side,
        )
        val scaled = if (cropped.width == size) {
            cropped
        } else {
            Bitmap.createScaledBitmap(cropped, size, size, true)
        }
        if (scaled != cropped) cropped.recycle()
        val output = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val radius = size / 2f
        canvas.drawCircle(radius, radius, radius, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(scaled, 0f, 0f, paint)
        if (!scaled.isRecycled) scaled.recycle()
        return output
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
            NotificationChannel(CALL_CHANNEL, "Appels Klambocore", NotificationManager.IMPORTANCE_MAX).apply {
                description = "Appels entrants, même écran verrouillé"
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
        const val ACTION_STOP_RING = "com.klambocore.klambo.STOP_RING"
        const val ACTION_DECLINE = "com.klambocore.klambo.DECLINE_CALL"
        const val ACTION_ONGOING = "com.klambocore.klambo.CALL_ONGOING"
        const val ACTION_IDLE = "com.klambocore.klambo.CALL_IDLE"
        const val EXTRA_CALL = "klambo_call_event"
        const val EXTRA_ACCEPT = "klambo_call_accept"
        const val EXTRA_NAME = "klambo_call_name"
        const val EXTRA_VIDEO = "klambo_call_video"
        private const val CALL_NOTIF_ID = 900001
        private const val PENDING_CALL_KEY = "flutter.klambo_pending_call"
        private const val CALL_CHANNEL = "klambo_calls_bg_v2"
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
