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
  static const badgeChannelId = "klambo_badge_v3";

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  int _unreadBadge = 0;
  int _messageNotifSeq = 1000;
  final Map<String, int> _messageNotifIds = {};
  DateTime? _localBadgeBumpAt;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  NotificationTapCallback? onTap;

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
        onTap?.call(response.payload);
      },
    );

    await _ensureAndroidChannels();
    _ready = true;
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
        description: "Compteur de messages non lus",
        importance: Importance.low,
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
      final status = await Permission.notification.request();
      granted = status.isGranted || status.isLimited;
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
      return Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
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
    final avatar = await _avatarBytes(avatarUrl);

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
          largeIcon: avatar == null ? null : ByteArrayAndroidBitmap(avatar),
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

    await _plugin.show(
      id: id,
      title: callerName,
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
          // Sonnerie / notif par défaut du téléphone (pas de raw custom).
          enableVibration: true,
          ticker: "$callerName — $label",
          visibility: NotificationVisibility.public,
          channelShowBadge: true,
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: playSound,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: "call|${callId ?? ""}",
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
      if (_unreadBadge <= 0) {
        await _plugin.cancel(id: 900002);
        return;
      }
      await _plugin.show(
        id: 900002,
        title: "Klambo",
        body: _unreadBadge == 1
            ? "1 message non lu"
            : "$_unreadBadge messages non lus",
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            badgeChannelId,
            "Badge non lus",
            channelDescription: "Compteur de messages non lus",
            importance: Importance.low,
            priority: Priority.low,
            playSound: false,
            enableVibration: false,
            number: _unreadBadge,
            channelShowBadge: true,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            silent: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: false,
            presentSound: false,
            presentBadge: true,
            badgeNumber: _unreadBadge,
          ),
        ),
      );
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
