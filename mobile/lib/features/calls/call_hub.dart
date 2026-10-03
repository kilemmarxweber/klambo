import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:klambo_messagerie/core/alert_prefs.dart";
import "package:klambo_messagerie/core/media_urls.dart";
import "package:klambo_messagerie/core/notification_service.dart";
import "package:klambo_messagerie/core/sound_service.dart";
import "package:klambo_messagerie/data/calls_repository.dart";
import "package:klambo_messagerie/data/messaging_repository.dart";
import "package:klambo_messagerie/data/messaging_socket.dart";
import "package:klambo_messagerie/features/auth/session_provider.dart";
import "package:klambo_messagerie/features/calls/call_controller.dart";
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
  })  : _messaging = messaging,
        _readActiveConversationId = readActiveConversationId,
        _readOrganizationIds = readOrganizationIds {
    presence = PresenceController();
    socket = MessagingSocket(token: token);
    controller = CallController(
      calls: calls,
      socket: socket,
      localUserId: localUserId,
    );
    controller.addListener(_onCallPhaseChanged);
    controller.onIncomingRing = (_) {
      unawaited(_alertIncomingCall());
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      final route = ModalRoute.of(nav.context);
      if (route?.settings.name == "/call") return;
      nav.push(
        MaterialPageRoute(
          settings: const RouteSettings(name: "/call"),
          fullscreenDialog: true,
          builder: (_) => CallScreen(controller: controller),
        ),
      );
    };
    socket.onMessageEvent = _onMessageEvent;
    socket.onPresenceEvent = presence.applyEvent;
    socket.onConnected = () {
      debugPrint("[hub] ws connected");
      final orgId = presence.organizationId ?? initialOrganizationId;
      if (orgId != null && orgId.isNotEmpty) {
        socket.subscribePresence(orgId);
        unawaited(_heartbeat(orgId));
      }
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
    _callPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_pollCalls());
    });
  }

  final String localUserId;
  final MessagingRepository _messaging;
  final String? Function() _readActiveConversationId;
  final List<String> Function()? _readOrganizationIds;
  Timer? _callPollTimer;
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

  Future<void> _pollCalls() async {
    if (controller.isDisposed) return;
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

  Future<void> _alertIncomingCall() async {
    unawaited(SoundService.instance.startRingtone());
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
    final body = event["bodyPreview"]?.toString() ??
        event["body"]?.toString() ??
        p["body"]?.toString() ??
        p["text"]?.toString() ??
        "Nouveau message";
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
    final phase = controller.phase;
    if (phase == CallPhase.ringingIn || phase == CallPhase.ringingOut) {
      unawaited(SoundService.instance.startRingtone());
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
      unawaited(SoundService.instance.startRingtone());
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
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      nav.push(
        MaterialPageRoute(
          settings: const RouteSettings(name: "/call"),
          fullscreenDialog: true,
          builder: (_) => CallScreen(controller: controller),
        ),
      );
    } catch (e) {
      debugPrint("[hub] startOutgoing failed: $e");
      await SoundService.instance.stopRingtone();
      rethrow;
    }
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
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
