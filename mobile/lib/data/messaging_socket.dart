import "dart:async";
import "dart:convert";

import "package:flutter/foundation.dart";
import "package:web_socket_channel/web_socket_channel.dart";
import "package:klambo_messagerie/core/config.dart";

typedef CallEventHandler = void Function(Map<String, dynamic> event);

/// Client WS messagerie + signaling appels + présence (avec reconnexion).
///
/// Destiné au **premier plan**. En arrière-plan, [setAppForeground] (false)
/// coupe la reconnexion agressive : FCM / FGS + sync HTTP au retour.
class MessagingSocket {
  MessagingSocket({required this.token});

  final String token;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _disposed = false;
  bool _connected = false;
  /// false = app en arrière-plan : pas de reconnect en boucle.
  bool _appForeground = true;
  DateTime? _lastPongAt;
  String? _subscribedOrgId;

  CallEventHandler? onCallEvent;
  CallEventHandler? onMessageEvent;
  CallEventHandler? onPresenceEvent;
  void Function()? onConnected;
  void Function()? onDisconnected;

  bool get isConnected => _connected;
  bool get appForeground => _appForeground;

  Uri get _uri {
    final base = Uri.parse(AppConfig.apiBaseUrl);
    final scheme = base.scheme == "https" ? "wss" : "ws";
    final host = base.host;
    final port = base.port == 3000 || base.port == 3001 ? 3010 : base.port;
    return Uri(
      scheme: scheme,
      host: host,
      port: port == 80 || port == 443 ? null : port,
      path: "/api/mobile/ws",
      queryParameters: {"token": token},
    );
  }

  void connect() {
    if (_disposed) return;
    if (!_appForeground) {
      debugPrint("[ws] skip connect (app background — FCM/FGS + sync on resume)");
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sub?.cancel();
    _pingTimer?.cancel();
    final wasConnected = _connected;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _connected = false;
    _lastPongAt = null;
    if (wasConnected) onDisconnected?.call();

    final uri = _uri;
    debugPrint("[ws] connecting ${uri.replace(queryParameters: {})}");
    try {
      _channel = WebSocketChannel.connect(uri);
    } catch (e) {
      debugPrint("[ws] connect throw $e");
      _scheduleReconnect();
      return;
    }

    _sub = _channel!.stream.listen(
      (raw) {
        try {
          final map = jsonDecode(raw as String) as Map<String, dynamic>;
          final type = map["type"]?.toString() ?? "";
          if (type == "connected") {
            _connected = true;
            _lastPongAt = DateTime.now();
            _reconnectAttempt = 0;
            onConnected?.call();
            final org = _subscribedOrgId;
            if (org != null && org.isNotEmpty) {
              sendJson({
                "type": "presence.subscribe",
                "organizationId": org,
              });
            }
            return;
          }
          if (type == "pong") {
            _lastPongAt = DateTime.now();
            return;
          }
          if (type == "presence" || type == "presence.snapshot") {
            onPresenceEvent?.call(map);
            return;
          }
          if (type.startsWith("call.")) {
            onCallEvent?.call(map);
            return;
          }
          if (type == "message.created" ||
              type == "message.updated" ||
              type == "message.delivered" ||
              type == "message.received" ||
              type == "message.read" ||
              type == "message.deleted" ||
              type == "conversation.updated" ||
              type == "typing") {
            onMessageEvent?.call(map);
          }
        } catch (e) {
          debugPrint("[ws] parse error $e");
        }
      },
      onError: (e) {
        debugPrint("[ws] error $e");
        _markDisconnected();
        _scheduleReconnect();
      },
      onDone: () {
        debugPrint("[ws] closed");
        _markDisconnected();
        _scheduleReconnect();
      },
      cancelOnError: true,
    );

    _ensurePingTimer();
  }

  void _ensurePingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!_connected || !_appForeground) return;
      final lastPong = _lastPongAt;
      if (lastPong != null &&
          DateTime.now().difference(lastPong) > const Duration(seconds: 55)) {
        debugPrint("[ws] pong timeout");
        _markDisconnected();
        _scheduleReconnect();
        return;
      }
      sendJson({"type": "ping"});
    });
  }

  void _scheduleReconnect() {
    if (_disposed || !_appForeground) return;
    _reconnectTimer?.cancel();
    final attempt = _reconnectAttempt.clamp(0, 6);
    final seconds = [2, 3, 5, 8, 13, 21, 30][attempt];
    _reconnectAttempt = attempt + 1;
    debugPrint("[ws] reconnect in ${seconds}s (attempt $_reconnectAttempt)");
    _reconnectTimer = Timer(Duration(seconds: seconds), connect);
  }

  /// Premier plan : assure le monitoring. Arrière-plan : stoppe la boucle
  /// de reconnect (FCM / FGS + sync HTTP au retour).
  void setAppForeground(bool foreground) {
    if (_disposed) return;
    if (_appForeground == foreground) {
      // Même état (ex. resume sans BG) : reconnecter si down, sinon
      // réarmer le ping si le timer a été annulé.
      if (foreground) {
        if (!_connected) {
          reconnectNow();
        } else if (_pingTimer == null || !(_pingTimer!.isActive)) {
          _ensurePingTimer();
          sendJson({"type": "ping"});
        }
      }
      return;
    }
    _appForeground = foreground;
    if (foreground) {
      debugPrint("[ws] app foreground → ensure socket");
      if (!_connected) {
        reconnectNow();
        return;
      }
      // Bug 1: après BG le ping est annulé ; sans le recréer, un socket
      // périmé (close non encore livré) n'est jamais sondé.
      _ensurePingTimer();
      final lastPong = _lastPongAt;
      if (lastPong == null ||
          DateTime.now().difference(lastPong) > const Duration(seconds: 55)) {
        debugPrint("[ws] stale after background → reconnect");
        reconnectNow();
      } else {
        sendJson({"type": "ping"});
      }
    } else {
      debugPrint("[ws] app background → pause reconnect loop");
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _pingTimer?.cancel();
      _pingTimer = null;
    }
  }

  void _markDisconnected() {
    final was = _connected;
    _connected = false;
    _lastPongAt = null;
    if (was) onDisconnected?.call();
  }

  void sendJson(Map<String, dynamic> data) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (e) {
      debugPrint("[ws] send failed $e");
    }
  }

  void subscribePresence(String organizationId) {
    _subscribedOrgId = organizationId;
    sendJson({
      "type": "presence.subscribe",
      "organizationId": organizationId,
    });
  }

  void queryPresence({
    required String organizationId,
    required List<String> userIds,
  }) {
    if (userIds.isEmpty) return;
    sendJson({
      "type": "presence.query",
      "organizationId": organizationId,
      "userIds": userIds,
    });
  }

  void sendTyping({
    required String organizationId,
    required String conversationId,
  }) {
    sendJson({
      "type": "typing",
      "organizationId": organizationId,
      "conversationId": conversationId,
    });
  }

  void sendCallSignal({
    required String type,
    required String organizationId,
    required String callId,
    required String toUserId,
    String? fromUserId,
    Map<String, dynamic>? payload,
  }) {
    sendJson({
      "type": type,
      "organizationId": organizationId,
      "callId": callId,
      "toUserId": toUserId,
      if (fromUserId != null && fromUserId.isNotEmpty) "fromUserId": fromUserId,
      if (payload != null) "payload": payload,
    });
  }

  /// Force une reconnexion immédiate (ex. retour au premier plan).
  ///
  /// Ne force **pas** `_appForeground` : un changement réseau en BG
  /// (via [CallHub]) ne doit pas rouvrir le WS Flutter en arrière-plan.
  void reconnectNow() {
    if (_disposed) return;
    _reconnectAttempt = 0;
    connect();
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _connected = false;
  }
}
