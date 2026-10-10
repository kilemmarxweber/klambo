import "dart:async";
import "dart:math" as math;
import "dart:ui" as ui;

import "package:app_badge_plus/app_badge_plus.dart";
import "package:dio/dio.dart";
import "package:flutter/foundation.dart";
import "package:flutter/widgets.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:klambo_messagerie/core/alert_prefs.dart";
import "package:permission_handler/permission_handler.dart";

bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

typedef NotificationTapCallback = void Function(String? payload);

/// Notifications locales (messages + appels) + badge launcher.
///
/// Canaux v6 : son **par défaut du téléphone** (fiable). Les canaux Android
/// sont immuables — un nouvel id force la recréation si l’ancien était muet.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const messagesChannelId = "klambo_messages_v8";
  static const callsChannelId = "klambo_calls_v6";
  static const badgeChannelId = "klambo_badge_v4";

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  int _unreadBadge = 0;
  int _messageNotifSeq = 1000;
  final Map<String, int> _messageNotifIds = {};
  DateTime? _localBadgeBumpAt;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  NotificationTapCallback? _onTap;
  /// Payloads en attente (cold start / taps avant que l'UI soit branchée).
  final List<String> _pendingTapPayloads = [];

  set onTap(NotificationTapCallback? callback) {
    _onTap = callback;
    if (callback != null && _pendingTapPayloads.isNotEmpty) {
      final pending = List<String>.from(_pendingTapPayloads);
      _pendingTapPayloads.clear();
      // Différer pour laisser ConversationsScreen finir son init.
      scheduleMicrotask(() {
        for (final payload in pending) {
          callback(payload);
        }
      });
    }
  }

  NotificationTapCallback? get onTap => _onTap;

  bool get isBackground =>
      _lifecycle == AppLifecycleState.paused ||
      _lifecycle == AppLifecycleState.inactive ||
      _lifecycle == AppLifecycleState.hidden ||
      _lifecycle == AppLifecycleState.detached;

  bool get isForeground =>
      _lifecycle == AppLifecycleState.resumed;

  void setLifecycle(AppLifecycleState state) {
    _lifecycle = state;
  }

  Future<void> init() async {
    if (_ready || kIsWeb) return;

    const androidInit = AndroidInitializationSettings("@mipmap/ic_launcher");
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        final action = response.actionId;
        final payload = response.payload;
        if (action == "decline") {
          // Annule la notif ; le hub coupera via hangup si déjà ringing.
          unawaited(cancelIncomingCallNotification());
          return;
        }
        // "accept" ou tap corps → ouvrir l'écran d'appel.
        _dispatchTap(payload);
      },
    );

    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        final payload = launch!.notificationResponse?.payload;
        _enqueuePendingTap(payload);
      }
    } catch (e) {
      debugPrint("[notif] launch details failed: $e");
    }

    await _ensureAndroidChannels();
    _ready = true;
  }

  void _enqueuePendingTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    // FIFO : ne pas écraser un tap plus ancien (cold start / taps rapides).
    if (!_pendingTapPayloads.contains(payload)) {
      _pendingTapPayloads.add(payload);
    }
  }

  void _dispatchTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final cb = _onTap;
    if (cb != null) {
      cb(payload);
    } else {
      _enqueuePendingTap(payload);
    }
  }

  /// Consomme le prochain payload cold-start / tap en attente (FIFO).
  String? consumePendingTap() {
    if (_pendingTapPayloads.isEmpty) return null;
    return _pendingTapPayloads.removeAt(0);
  }

  /// Annule la notif message de ce fil + rafraîchit le badge launcher.
  Future<void> cancelConversationNotifications(String? conversationId) async {
    if (!_ready || kIsWeb) return;
    if (conversationId == null || conversationId.isEmpty) return;
    final id = _messageNotifIds.remove(conversationId);
    if (id != null) {
      await _plugin.cancel(id: id);
    }
  }

  Future<void> _ensureAndroidChannels() async {
    if (!_isAndroid) return;
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;

    // Son = défaut appareil (pas de RawResource) → marche même si asset KO.
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        messagesChannelId,
        "Messages Klambocore",
        description: "Nouveaux messages, son du téléphone",
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
        audioAttributesUsage: AudioAttributesUsage.notification,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        callsChannelId,
        "Appels Klambo",
        description: "Appels entrants (sonnerie système)",
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        badgeChannelId,
        "Badge non lus",
        description: "Compteur de messages non lus (silencieux)",
        importance: Importance.min,
        playSound: false,
        enableVibration: false,
        showBadge: true,
      ),
    );
  }

  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;

    var granted = false;

    if (_isAndroid) {
      try {
        final statuses = await [
          Permission.notification,
          Permission.microphone,
          Permission.camera,
          Permission.bluetoothConnect,
          Permission.ignoreBatteryOptimizations,
          Permission.scheduleExactAlarm,
          Permission.systemAlertWindow,
        ].request();
        final notif = statuses[Permission.notification];
        granted = notif?.isGranted == true || notif?.isLimited == true;
      } catch (_) {
        final status = await Permission.notification.request();
        granted = status.isGranted || status.isLimited;
      }
      try {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await android?.requestNotificationsPermission();
      } catch (_) {}
    } else if (_isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      granted = await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    await AlertPrefs.instance.markPermissionAsked();
    return granted;
  }

  Future<bool> areNotificationsAllowed() async {
    if (kIsWeb) return false;
    if (_isAndroid) {
      return Permission.notification.isGranted;
    }
    if (_isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final opts = await ios?.checkPermissions();
      return opts?.isEnabled ?? false;
    }
    return false;
  }

  Future<Uint8List?> _avatarBytes(String? url) async {
    if (url == null || url.isEmpty || url.startsWith("data:")) return null;
    try {
      final res = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 6),
          responseType: ResponseType.bytes,
          followRedirects: true,
        ),
      ).get<List<int>>(url);
      final data = res.data;
      if (data == null || data.length < 32 || data.length > 2000000) {
        return null;
      }
      // PNG circulaire (coins transparents) pour largeIcon / Person Android.
      return await _circleCropPng(Uint8List.fromList(data));
    } catch (_) {
      return null;
    }
  }

  /// Recadre en cercle 192×192 PNG — forme ronde dans la notif.
  Future<Uint8List?> _circleCropPng(Uint8List bytes, {int size = 192}) async {
    ui.Image? src;
    ui.Image? out;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      src = frame.image;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final dst = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
      canvas.clipPath(Path()..addOval(dst));
      final srcW = src.width.toDouble();
      final srcH = src.height.toDouble();
      final side = math.min(srcW, srcH);
      final srcRect = Rect.fromLTWH(
        (srcW - side) / 2,
        (srcH - side) / 2,
        side,
        side,
      );
      canvas.drawImageRect(
        src,
        srcRect,
        dst,
        Paint()..isAntiAlias = true..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      out = await picture.toImage(size, size);
      final bd = await out.toByteData(format: ui.ImageByteFormat.png);
      return bd?.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      src?.dispose();
      out?.dispose();
    }
  }

  StyleInformation _messageStyle({
    required String title,
    required String body,
    Uint8List? circleAvatar,
  }) {
    if (_isAndroid && circleAvatar != null && circleAvatar.isNotEmpty) {
      final sender = Person(
        name: title,
        icon: ByteArrayAndroidIcon(circleAvatar),
        important: true,
      );
      return MessagingStyleInformation(
        const Person(name: "Moi"),
        conversationTitle: title,
        groupConversation: false,
        messages: <Message>[
          Message(body, DateTime.now(), sender),
        ],
      );
    }
    return BigTextStyleInformation(
      body,
      contentTitle: title,
      summaryText: "Klambocore",
    );
  }

  Future<void> showMessageNotification({
    required String title,
    required String body,
    String? conversationId,
    String? organizationId,
    String? avatarUrl,
    int? badgeCount,
    bool silent = false,
  }) async {
    if (!_ready || kIsWeb) return;
    if (!AlertPrefs.instance.messageNotificationsEnabled) return;

    final thread = conversationId ?? title;
    final previousId = _messageNotifIds[thread];
    if (previousId != null) {
      await _plugin.cancel(id: previousId);
    }
    final id = 1000 + (_messageNotifSeq++ % 80000);
    _messageNotifIds[thread] = id;
    final payload = [
      "message",
      organizationId ?? "",
      conversationId ?? "",
    ].join("|");
    final playSound = !silent && AlertPrefs.instance.soundsEnabled;
    final count = badgeCount ?? _unreadBadge;
    // Afficher tout de suite — ne pas bloquer sur le téléchargement d'avatar.
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          messagesChannelId,
          "Messages Klambocore",
          channelDescription: "Nouveaux messages, son du téléphone",
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.message,
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title,
            summaryText: "Klambocore",
          ),
          playSound: playSound,
          // null = son de notification par défaut du device
          enableVibration: !silent,
          ticker: "$title: $body",
          visibility: NotificationVisibility.public,
          number: count > 0 ? count : null,
          channelShowBadge: true,
          audioAttributesUsage: AudioAttributesUsage.notification,
          autoCancel: true,
          onlyAlertOnce: false,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: playSound,
          // Son défaut iOS si pas de nom de fichier custom.
          badgeNumber: count > 0 ? count : null,
          threadIdentifier: conversationId,
          interruptionLevel: InterruptionLevel.active,
        ),
      ),
      payload: payload,
    );

    // Avatar circulaire en arrière-plan (rafraîchit la notif si encore visible).
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      unawaited(() async {
        final avatar = await _avatarBytes(avatarUrl);
        if (avatar == null) return;
        if (_messageNotifIds[thread] != id) return;
        try {
          await _plugin.show(
            id: id,
            title: title,
            body: body,
            notificationDetails: NotificationDetails(
              android: AndroidNotificationDetails(
                messagesChannelId,
                "Messages Klambocore",
                channelDescription: "Nouveaux messages, son du téléphone",
                importance: Importance.max,
                priority: Priority.max,
                category: AndroidNotificationCategory.message,
                largeIcon: ByteArrayAndroidBitmap(avatar),
                styleInformation: _messageStyle(
                  title: title,
                  body: body,
                  circleAvatar: avatar,
                ),
                playSound: false,
                enableVibration: false,
                number: count > 0 ? count : null,
                channelShowBadge: true,
                autoCancel: true,
                onlyAlertOnce: true,
              ),
              iOS: DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: false,
                badgeNumber: count > 0 ? count : null,
                threadIdentifier: conversationId,
              ),
            ),
            payload: payload,
          );
        } catch (_) {}
      }());
    }
  }

  Future<void> showIncomingCallNotification({
    required String callerName,
    required String kind,
    String? callId,
  }) async {
    if (!_ready || kIsWeb) return;
    if (!AlertPrefs.instance.callNotificationsEnabled) return;

    final label = kind.toUpperCase() == "VIDEO"
        ? "Appel vidéo entrant"
        : "Appel audio entrant";
    const id = 900001;
    final playSound = AlertPrefs.instance.soundsEnabled;
    final name = callerName.trim().isEmpty ? "Klambo" : callerName.trim();

    await _plugin.show(
      id: id,
      title: name,
      body: label,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          callsChannelId,
          "Appels Klambo",
          channelDescription: "Appels entrants (sonnerie système)",
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          playSound: playSound,
          enableVibration: true,
          ticker: "$name — $label",
          visibility: NotificationVisibility.public,
          channelShowBadge: true,
          timeoutAfter: null,
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
          actions: const <AndroidNotificationAction>[
            AndroidNotificationAction(
              "decline",
              "Refuser",
              cancelNotification: true,
              showsUserInterface: false,
            ),
            AndroidNotificationAction(
              "accept",
              "Décrocher",
              cancelNotification: true,
              showsUserInterface: true,
            ),
          ],
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: playSound,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: "call|${callId ?? ""}|$kind",
    );
  }

  Future<void> cancelIncomingCallNotification() async {
    if (!_ready || kIsWeb) return;
    await _plugin.cancel(id: 900001);
  }

  Future<void> bumpBadge([int by = 1]) async {
    final next = (_unreadBadge + by).clamp(0, 9999);
    _localBadgeBumpAt = DateTime.now();
    await updateBadge(next);
  }

  Future<void> syncBadgeFromServer(int serverTotal) async {
    final server = serverTotal < 0 ? 0 : serverTotal;
    final bumpAt = _localBadgeBumpAt;
    if (bumpAt != null &&
        DateTime.now().difference(bumpAt) < const Duration(seconds: 20) &&
        server < _unreadBadge) {
      debugPrint(
        "[badge] keep local=$_unreadBadge (server=$server still stale)",
      );
      return;
    }
    if (server >= _unreadBadge || bumpAt == null) {
      _localBadgeBumpAt = null;
    }
    await updateBadge(server);
  }

  Future<void> updateBadge(int count) async {
    _unreadBadge = count < 0 ? 0 : count;
    if (kIsWeb) return;

    try {
      await AppBadgePlus.updateBadge(_unreadBadge);
    } catch (e) {
      debugPrint("[badge] AppBadgePlus failed: $e");
    }

    if (!_ready) return;
    try {
      // Retire l'ancienne notif fixe Android (« X messages non lus »).
      await _plugin.cancel(id: 900002);
      if (_unreadBadge <= 0) return;
      // iOS : badge icône sans alerte. Android : AppBadgePlus seulement.
      if (_isIOS) {
        await _plugin.show(
          id: 900002,
          title: "",
          body: "",
          notificationDetails: NotificationDetails(
            iOS: DarwinNotificationDetails(
              presentAlert: false,
              presentSound: false,
              presentBadge: true,
              badgeNumber: _unreadBadge,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("[badge] silent notif failed: $e");
    }
  }

  Future<void> clearBadge() {
    _localBadgeBumpAt = null;
    return updateBadge(0);
  }

  int get unreadBadge => _unreadBadge;
}
