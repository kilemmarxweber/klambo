import "dart:async";
import "dart:convert";

import "package:connectivity_plus/connectivity_plus.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:klambo_messagerie/core/alert_prefs.dart";
import "package:klambo_messagerie/core/background_alerts.dart";
import "package:klambo_messagerie/core/lock_screen.dart";
import "package:klambo_messagerie/core/media_urls.dart";
import "package:klambo_messagerie/core/notification_service.dart";
import "package:klambo_messagerie/core/sound_service.dart";
import "package:klambo_messagerie/data/calls_repository.dart";
import "package:klambo_messagerie/data/messaging_repository.dart";
import "package:klambo_messagerie/data/messaging_socket.dart";
import "package:klambo_messagerie/features/auth/session_provider.dart";
import "package:klambo_messagerie/features/calls/call_controller.dart";
import "package:klambo_messagerie/features/calls/call_identity.dart";
import "package:klambo_messagerie/features/calls/call_signal_policy.dart";
import "package:klambo_messagerie/features/calls/call_screen.dart";
import "package:klambo_messagerie/features/chat/active_chat_provider.dart";
import "package:klambo_messagerie/features/presence/presence_controller.dart";

final callsRepositoryProvider = Provider<CallsRepository>(
  (ref) => CallsRepository(ref.watch(apiClientProvider)),
);

/// Clé navigateur globale pour pousser l'écran d'appel entrant.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final callHubProvider = Provider<CallHub?>((ref) {
  // Ne recréer le hub que si le token / userId change (pas à chaque refreshMe).
  final creds = ref.watch(
    sessionProvider.select((s) {
      final user = s.me?["user"];
      final userId = user is Map ? user["id"]?.toString() : null;
      return (token: s.token, userId: userId);
    }),
  );
  final token = creds.token;
  final userId = creds.userId;
  if (token == null || token.isEmpty || userId == null || userId.isEmpty) {
    return null;
  }

  final hub = CallHub(
    token: token,
    localUserId: userId,
    calls: ref.read(callsRepositoryProvider),
    messaging: ref.read(messagingRepositoryProvider),
    initialOrganizationId: ref.read(sessionProvider).activeOrgId,
    readActiveConversationId: () => ref.read(activeConversationIdProvider),
    readOrganizationIds: () {
      return ref
          .read(sessionProvider)
          .messagingOrganizations
          .map((org) => org["id"]?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList();
    },
  );
  ref.onDispose(hub.dispose);
  return hub;
});

final presenceProvider = Provider<PresenceController?>((ref) {
  return ref.watch(callHubProvider)?.presence;
});

/// Flux d'événements messagerie (message.*, conversation.updated, typing, call.*…).
final messagingEventsProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final hub = ref.watch(callHubProvider);
  if (hub == null) return const Stream.empty();
  return hub.messageEvents;
});

class CallHub {
  CallHub({
    required String token,
    required this.localUserId,
    required CallsRepository calls,
    required MessagingRepository messaging,
    String? initialOrganizationId,
    required String? Function() readActiveConversationId,
    List<String> Function()? readOrganizationIds,
  })  : _calls = calls,
        _messaging = messaging,
        _readActiveConversationId = readActiveConversationId,
        _readOrganizationIds = readOrganizationIds {
    presence = PresenceController();
    socket = MessagingSocket(token: token);
    final identity = CallIdentity(calls: calls);
    controller = CallController(
      calls: calls,
      socket: socket,
      localUserId: localUserId,
      identity: identity,
    );
    unawaited(identity.ensureRegistered());
    unawaited(messaging.ensureMessageKeys());
    _bindCallKit();
    unawaited(_registerPushToken());
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 400), consumeNativeCall),
    );
    controller.addListener(_onCallPhaseChanged);
    controller.onIncomingRing = (_) {
      unawaited(_alertIncomingCall());
      showCallScreen();
    };
    socket.onMessageEvent = _onMessageEvent;
    socket.onPresenceEvent = presence.applyEvent;
    socket.onConnected = () {
      debugPrint("[hub] ws connected");
      _emitLink("link.up");
      _scheduleCallFallback();
      final orgId = presence.organizationId ?? initialOrganizationId;
      if (orgId != null && orgId.isNotEmpty) {
        socket.subscribePresence(orgId);
        unawaited(_heartbeat(orgId));
      }
      if (controller.isBusy) {
        unawaited(controller.pullRemoteSignal());
      }
    };
    socket.onDisconnected = () {
      debugPrint("[hub] ws disconnected");
      _emitLink("link.down");
      _scheduleCallFallback();
    };
    if (initialOrganizationId != null && initialOrganizationId.isNotEmpty) {
      presence.setOrganization(initialOrganizationId);
      unawaited(_heartbeat(initialOrganizationId));
    }
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final orgId = presence.organizationId ?? initialOrganizationId;
      if (orgId != null && orgId.isNotEmpty) {
        unawaited(_heartbeat(orgId));
      }
    });
    socket.connect();
    _watchNetwork();
    _scheduleCallFallback();
  }

  String? _callPollKey;

  void _emitLink(String type) {
    if (_messageController.isClosed) return;
    _messageController.add({"type": type});
  }

  /// Aucune requête d'appel tant que le WebSocket répond.
  /// Sinon un intervalle court en communication, long au repos.
  void _scheduleCallFallback() {
    final delay = callFallbackDelay(
      socketConnected: socket.isConnected,
      inCall: controller.isBusy,
    );
    final key = delay == null ? "off" : "${delay.inSeconds}";
    if (key == _callPollKey &&
        (delay == null || _callPollTimer?.isActive == true)) {
      return;
    }
    _callPollKey = key;
    _callPollTimer?.cancel();
    _callPollTimer = null;
    if (delay == null) return;
    _callPollTimer = Timer(delay, () async {
      _callPollKey = null;
      try {
        await _pollCalls();
      } finally {
        _scheduleCallFallback();
      }
    });
  }

  final String localUserId;
  final CallsRepository _calls;
  final MessagingRepository _messaging;
  static const _callKit = MethodChannel("klambo/callkit");
  final String? Function() _readActiveConversationId;
  final List<String> Function()? _readOrganizationIds;
  Timer? _callPollTimer;
  StreamSubscription<List<ConnectivityResult>>? _networkSub;
  List<ConnectivityResult>? _lastNetwork;
  late final MessagingSocket socket;
  late final CallController controller;
  late final PresenceController presence;
  Timer? _heartbeatTimer;

  final _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final Set<String> _alertedMessageKeys = {};
  Stream<Map<String, dynamic>> get messageEvents => _messageController.stream;

  Future<void> _heartbeat(String organizationId) {
    return _messaging.presenceHeartbeat(organizationId);
  }

  void _bindCallKit() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _callKit.setMethodCallHandler((call) async {
      final args = call.arguments;
      final map = args is Map ? Map<String, dynamic>.from(args) : const {};
      final callId = map["callId"]?.toString();
      if (call.method == "answered") {
        if (callId != null &&
            controller.active?.callId == callId &&
            controller.phase == CallPhase.ringingIn) {
          await controller.acceptIncoming();
        }
      } else if (call.method == "ended") {
        if (controller.isBusy &&
            (callId == null || controller.active?.callId == callId)) {
          await controller.hangup();
        }
      }
    });
  }

  Future<void> _registerPushToken() async {
    final token = await BackgroundAlerts.pushToken();
    if (token == null || token.isEmpty) return;
    try {
      await _calls.registerPushToken(token: token, platform: "android");
    } catch (e) {
      debugPrint("[hub] push token: $e");
    }
  }

  /// Offre livrée par la notification Android. Le média n'est créé qu'au décrochage.
  Future<void> consumeNativeCall() async {
    final pending = await BackgroundAlerts.takePendingCall();
    if (pending == null || controller.isDisposed) return;
    final raw = pending["event"]?.toString();
    if (raw == null || raw.isEmpty) return;
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map) return;
    await controller.handleIncomingOffer(Map<String, dynamic>.from(decoded));
    if (shouldAutoAcceptNative(
      requested: pending["autoAccept"] == true,
      ringingIn: controller.phase == CallPhase.ringingIn,
    )) {
      await controller.acceptIncoming();
    }
    if (controller.isBusy) showCallScreen();
  }

  void _watchNetwork() {
    _networkSub = Connectivity().onConnectivityChanged.listen((results) {
      final prev = _lastNetwork;
      _lastNetwork = results;
      if (prev == null) return;
      if (!_sameNetwork(prev, results)) {
        controller.onNetworkChanged();
      }
    });
  }

  bool _sameNetwork(List<ConnectivityResult> a, List<ConnectivityResult> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _pollCalls() async {
    if (controller.isDisposed) return;
    if (!shouldPollCalls(socketConnected: socket.isConnected)) return;
    final orgs = _readOrganizationIds?.call() ?? const <String>[];
    try {
      if (controller.isBusy) {
        await controller.pullRemoteSignal();
      } else {
        await controller.pollIncoming(orgs);
      }
    } catch (e) {
      debugPrint("[hub] call poll: $e");
    }
  }

  Future<void>? _incomingRingTask;

  /// Coupe la sonnerie du service, puis une seule sonnerie Flutter.
  Future<void> _playIncomingRing() {
    final next = (_incomingRingTask ?? Future<void>.value()).then((_) async {
      await BackgroundAlerts.stopNativeRing();
      await SoundService.instance.startRingtone(incoming: true);
    });
    _incomingRingTask = next;
    return next;
  }

  Future<void> _alertIncomingCall() async {
    unawaited(setLockScreenVisible(true));
    unawaited(_playIncomingRing());
    final peer = controller.active?.peerName?.trim();
    final name = (peer != null && peer.isNotEmpty) ? peer : "Klambo";
    unawaited(
      NotificationService.instance.showIncomingCallNotification(
        callerName: name,
        kind: controller.active?.kind ?? "AUDIO",
        callId: controller.active?.callId,
      ),
    );
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        NotificationService.instance.isBackground) {
      unawaited(
        _callKit.invokeMethod<void>("reportIncoming", {
          "callId": controller.active?.callId,
          "name": name,
          "video": controller.active?.kind == "VIDEO",
        }),
      );
    }
  }

  void _onMessageEvent(Map<String, dynamic> event) {
    if (!_messageController.isClosed) {
      _messageController.add(event);
    }

    final type = event["type"]?.toString() ?? "";

    if (type == "call.offer" &&
        event["toUserId"]?.toString() == localUserId) {
      unawaited(_alertIncomingCall());
      return;
    }

    if (type == "message.created") {
      unawaited(_onIncomingMessage(event));
    }
  }

  Future<void> _onIncomingMessage(Map<String, dynamic> event) async {
    final payload = event["payload"];
    final message = event["message"];
    final p = payload is Map
        ? Map<String, dynamic>.from(payload)
        : message is Map
            ? Map<String, dynamic>.from(message)
            : const <String, dynamic>{};

    final senderId = _firstId([
      event["senderId"],
      p["senderId"],
      p["authorId"],
      p["sender"] is Map ? (p["sender"] as Map)["id"] : null,
      event["sender"] is Map ? (event["sender"] as Map)["id"] : null,
    ]);
    if (senderId != null && senderId == localUserId) return;

    final conversationId = event["conversationId"]?.toString() ??
        p["conversationId"]?.toString();
    final organizationId = event["organizationId"]?.toString() ??
        p["organizationId"]?.toString();
    final senderName = event["senderName"]?.toString() ??
        p["senderName"]?.toString() ??
        (p["sender"] is Map ? p["sender"]["name"]?.toString() : null) ??
        "Klambo";
    final avatarUrl = _imageUrl([
      event["senderImage"],
      p["senderImage"],
      p["image"],
      p["sender"] is Map ? (p["sender"] as Map)["image"] : null,
      event["sender"] is Map ? (event["sender"] as Map)["image"] : null,
    ]);
    final rawBody = event["bodyPreview"]?.toString() ??
        event["body"]?.toString() ??
        p["body"]?.toString() ??
        p["text"]?.toString() ??
        "Nouveau message";
    final body = rawBody.startsWith("k1.") ? "Message" : rawBody;
    final messageId = _firstId([
      p["id"],
      p["messageId"],
      event["messageId"],
    ]);
    final created = p["createdAt"]?.toString() ?? event["createdAt"]?.toString() ?? "";
    final altKey = "${conversationId ?? ""}|$created|$body";
    final dedupeKey = (messageId != null && messageId.isNotEmpty)
        ? messageId
        : altKey;

    await alertIncomingMessage(
      dedupeKey: dedupeKey,
      aliasKey: dedupeKey == altKey ? null : altKey,
      title: senderName,
      body: body,
      avatarUrl: avatarUrl,
      conversationId: conversationId,
      organizationId: organizationId,
    );
  }

  /// Empêche un message envoyé par nous de sonner quand la liste se rafraîchit.
  void rememberIncomingMessage(String dedupeKey) {
    if (dedupeKey.isEmpty) return;
    _alertedMessageKeys.add(dedupeKey);
  }

  /// Son (et notif si on n'est pas dans le fil) pour un message reçu.
  /// Appelé par le websocket et par le rafraîchissement des listes.
  Future<void> alertIncomingMessage({
    required String dedupeKey,
    String? aliasKey,
    required String title,
    required String body,
    String? avatarUrl,
    String? conversationId,
    String? organizationId,
  }) async {
    if (dedupeKey.isEmpty) return;
    final keys = <String>{
      dedupeKey,
      if (aliasKey != null && aliasKey.isNotEmpty) aliasKey,
    };
    if (keys.any(_alertedMessageKeys.contains)) {
      _alertedMessageKeys.addAll(keys);
      return;
    }
    _alertedMessageKeys.addAll(keys);
    if (_alertedMessageKeys.length > 400) {
      _alertedMessageKeys.remove(_alertedMessageKeys.first);
    }

    if (!AlertPrefs.instance.messageNotificationsEnabled &&
        !AlertPrefs.instance.soundsEnabled) {
      return;
    }

    final activeId = _readActiveConversationId();
    final inActiveChat =
        conversationId != null && conversationId == activeId;
    final foreground = !NotificationService.instance.isBackground;

    final nextBadge =
        NotificationService.instance.unreadBadge + (inActiveChat ? 0 : 1);
    if (!inActiveChat) {
      unawaited(NotificationService.instance.bumpBadge(1));
    }

    final showNotif = AlertPrefs.instance.messageNotificationsEnabled &&
        !(inActiveChat && foreground);
    if (!showNotif) return;

    await NotificationService.instance.showMessageNotification(
      title: title,
      body: body,
      avatarUrl: avatarUrl,
      conversationId: conversationId,
      organizationId: organizationId,
      badgeCount: nextBadge > 0 ? nextBadge : 1,
      silent: !AlertPrefs.instance.soundsEnabled,
    );
  }

  String? _firstId(List<dynamic> values) {
    for (final value in values) {
      final id = value?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  String? _imageUrl(List<dynamic> values) {
    for (final value in values) {
      final url = resolveImageUrl(value);
      if (url != null) return url;
    }
    return null;
  }

  void _onCallPhaseChanged() {
    _scheduleCallFallback();
    final phase = controller.phase;
    final overLock = phase == CallPhase.ringingIn ||
        phase == CallPhase.ringingOut ||
        phase == CallPhase.connecting ||
        phase == CallPhase.active;
    unawaited(setLockScreenVisible(overLock));
    final callLive =
        phase == CallPhase.connecting || phase == CallPhase.active;
    if (callLive) {
      final peer = controller.active?.peerName?.trim();
      final name = (peer != null && peer.isNotEmpty) ? peer : "Klambo";
      unawaited(
        BackgroundAlerts.setCallOngoing(
          name: name,
          video: controller.active?.kind == "VIDEO",
        ),
      );
    } else if (phase == CallPhase.idle || phase == CallPhase.ended) {
      unawaited(BackgroundAlerts.setCallIdle());
      final callId = controller.active?.callId;
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS &&
          callId != null) {
        unawaited(_callKit.invokeMethod<void>("end", {"callId": callId}));
      }
    }
    if (phase == CallPhase.ringingIn || phase == CallPhase.ringingOut) {
      if (phase == CallPhase.ringingIn) {
        unawaited(_playIncomingRing());
      } else {
        unawaited(SoundService.instance.startRingtone(incoming: false));
      }
      if (phase == CallPhase.ringingIn) {
        final peer = controller.active?.peerName?.trim();
        final name = (peer != null && peer.isNotEmpty) ? peer : "Klambo";
        unawaited(
          NotificationService.instance.showIncomingCallNotification(
            callerName: name,
            kind: controller.active?.kind ?? "AUDIO",
            callId: controller.active?.callId,
          ),
        );
      }
    } else {
      unawaited(SoundService.instance.stopRingtone());
      unawaited(NotificationService.instance.cancelIncomingCallNotification());
    }
  }

  void setActiveOrganization(String organizationId) {
    presence.setOrganization(organizationId);
    socket.subscribePresence(organizationId);
    unawaited(_heartbeat(organizationId));
  }

  Future<void> refreshPeerPresence({
    required String organizationId,
    required String userId,
  }) async {
    setActiveOrganization(organizationId);
    socket.queryPresence(organizationId: organizationId, userIds: [userId]);
  }

  Future<void> startOutgoing({
    required String organizationId,
    required String calleeId,
    required String kind,
    String? conversationId,
    String? peerName,
    String? callerName,
  }) async {
    try {
      // S'assure que le WS est vivant avant de sonner « dans le vide ».
      if (!socket.isConnected) {
        socket.reconnectNow();
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
      await refreshPeerPresence(
        organizationId: organizationId,
        userId: calleeId,
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final online = presence.isOnline(calleeId);
      if (!online) {
        debugPrint(
          "[hub] callee $calleeId appears offline — offer will still be sent/retried",
        );
      }
      unawaited(SoundService.instance.startRingtone(incoming: false));
      await controller.startOutgoing(
        organizationId: organizationId,
        calleeId: calleeId,
        kind: kind,
        conversationId: conversationId,
        peerName: peerName,
        callerName: callerName,
      );
      if (controller.isDisposed ||
          controller.phase == CallPhase.idle ||
          controller.phase == CallPhase.ended) {
        await SoundService.instance.stopRingtone();
        return;
      }
      if (!online) {
        controller.setStatusHint(
          "Contact hors ligne — il doit avoir Klambo ouvert pour décrocher",
        );
      }
      showCallScreen();
    } catch (e) {
      debugPrint("[hub] startOutgoing failed: $e");
      await SoundService.instance.stopRingtone();
      rethrow;
    }
  }

  /// Range l'écran, y compris pendant la sonnerie, sans couper l'appel.
  void minimizeCall() {
    if (controller.isDisposed || !controller.isBusy || controller.minimized) {
      return;
    }
    controller.setMinimized(true);
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.popUntil((route) => route.settings.name != "/call");
  }

  /// Rouvre l'écran d'appel sans en créer un second.
  void showCallScreen() {
    if (controller.isDisposed || !controller.isBusy) return;
    controller.setMinimized(false);
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    var visible = false;
    nav.popUntil((route) {
      visible = route.settings.name == "/call";
      return true;
    });
    if (visible) return;
    nav.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: "/call"),
        fullscreenDialog: true,
        builder: (_) => CallScreen(controller: controller),
      ),
    );
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    unawaited(_networkSub?.cancel());
    _networkSub = null;
    _callPollTimer?.cancel();
    _callPollTimer = null;
    controller.removeListener(_onCallPhaseChanged);
    controller.onIncomingRing = null;
    unawaited(SoundService.instance.stopRingtone());
    unawaited(NotificationService.instance.cancelIncomingCallNotification());
    // Teardown synchrone pour éviter crash WebRTC au balayage / dispose.
    try {
      controller.forceTeardown();
    } catch (_) {}
    try {
      if (!_messageController.isClosed) {
        _messageController.close();
      }
    } catch (_) {}
    try {
      controller.dispose();
    } catch (_) {}
    try {
      socket.dispose();
    } catch (_) {}
    try {
      presence.dispose();
    } catch (_) {}
  }

  /// Appelé quand l'OS tue / met l'app en detached (balayage recent apps).
  Future<void> onAppClosing() async {
    try {
      await SoundService.instance.stopRingtone();
    } catch (_) {}
    try {
      await NotificationService.instance.cancelIncomingCallNotification();
    } catch (_) {}
    try {
      if (controller.isBusy) {
        await controller.hangup();
      } else {
        controller.forceTeardown();
      }
    } catch (_) {
      try {
        controller.forceTeardown();
      } catch (_) {}
    }
  }
}
