import "dart:async";

import "package:flutter/foundation.dart";

class PresenceInfo {
  const PresenceInfo({
    required this.userId,
    required this.online,
    this.lastSeenAt,
  });

  final String userId;
  final bool online;
  final DateTime? lastSeenAt;

  PresenceInfo copyWith({bool? online, DateTime? lastSeenAt}) {
    return PresenceInfo(
      userId: userId,
      online: online ?? this.online,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }
}

/// Suivi présence en ligne (WS + snapshot REST).
class PresenceController extends ChangeNotifier {
  static const _onlineFreshness = Duration(minutes: 2);

  final Map<String, PresenceInfo> _byUser = {};
  Timer? _expiryTimer;
  String? _organizationId;

  /// La présence REST reste utilisable quand le serveur WebSocket est indisponible.
  bool _networkUp = true;
  bool _socketUp = false;

  String? get organizationId => _organizationId;

  bool get linkUp => _networkUp;
  bool get socketUp => _socketUp;

  PresenceInfo? of(String userId) {
    final info = _byUser[userId];
    if (info == null) return null;
    if (info.online && (!linkUp || !_isFresh(info))) {
      return PresenceInfo(
        userId: info.userId,
        online: false,
        lastSeenAt: info.lastSeenAt,
      );
    }
    return info;
  }

  bool isOnline(String userId) {
    final info = _byUser[userId];
    if (!linkUp || info == null || !info.online) return false;
    return _isFresh(info);
  }

  DateTime? lastSeenAt(String userId) => _byUser[userId]?.lastSeenAt;

  /// Appelé quand le WebSocket local tombe / revient.
  void setLinkUp(bool up) {
    _updateLink(socketUp: up);
    if (up) setNetworkUp(true);
  }

  /// Un réseau absent masque immédiatement la présence. Les snapshots REST
  /// peuvent la rétablir sans attendre la reconnexion du WebSocket.
  void setNetworkUp(bool up) {
    _updateLink(networkUp: up);
  }

  void _updateLink({bool? networkUp, bool? socketUp}) {
    final wasUp = linkUp;
    if (networkUp != null) _networkUp = networkUp;
    if (socketUp != null) _socketUp = socketUp;
    if (wasUp == linkUp) return;
    notifyListeners();
  }

  void setOrganization(String organizationId) {
    if (_organizationId == organizationId) return;
    _organizationId = organizationId;
    // Ne pas vider le cache : évite un flash « hors ligne » pendant le refresh.
    notifyListeners();
  }

  void applyEvent(Map<String, dynamic> event) {
    setNetworkUp(true);
    final type = event["type"]?.toString() ?? "";
    final payload = event["payload"];
    final data = payload is Map
        ? <String, dynamic>{...event, ...Map<String, dynamic>.from(payload)}
        : event;
    if (type == "presence.snapshot") {
      final items = event["items"] ??
          (payload is Map ? payload["items"] : null);
      if (items is! List) return;
      for (final raw in items) {
        if (raw is! Map) continue;
        _upsert(
          userId: _userId(raw),
          status: raw["status"]?.toString(),
          lastSeenRaw: raw["lastSeenAt"]?.toString(),
          onlineFlag: raw["online"] is bool ? raw["online"] as bool : null,
        );
      }
      notifyListeners();
      return;
    }

    if (type != "presence") return;
    // Accepte les événements de toutes les orgs : un user connecté
    // à l’app est considéré en ligne pour le chat.
    _upsert(
      userId: _userId(data),
      status: data["status"]?.toString(),
      lastSeenRaw: data["lastSeenAt"]?.toString(),
    );
    notifyListeners();
  }

  void applyRestItems(List<dynamic> items) {
    // Une réponse REST réussie prouve que l'API est joignable, même si le
    // plugin de connectivité ou le WebSocket a signalé une coupure.
    setNetworkUp(true);
    for (final raw in items) {
      if (raw is! Map) continue;
      _upsert(
        userId: _userId(raw),
        status: raw["status"]?.toString(),
        lastSeenRaw: raw["lastSeenAt"]?.toString(),
        onlineFlag: raw["online"] is bool ? raw["online"] as bool : null,
      );
    }
    notifyListeners();
  }

  String? _userId(Map raw) {
    final user = raw["user"];
    return raw["userId"]?.toString() ??
        raw["user_id"]?.toString() ??
        (user is Map ? user["id"]?.toString() : null);
  }

  void _upsert({
    required String? userId,
    String? status,
    String? lastSeenRaw,
    bool? onlineFlag,
  }) {
    if (userId == null || userId.isEmpty) return;
    final lastSeen =
        lastSeenRaw != null ? DateTime.tryParse(lastSeenRaw)?.toLocal() : null;
    final normalizedStatus = status?.toUpperCase();
    final online = onlineFlag ??
        (normalizedStatus == "ONLINE" || normalizedStatus == "CONNECTED");
    final prev = _byUser[userId];
    _byUser[userId] = PresenceInfo(
      userId: userId,
      online: online,
      lastSeenAt: lastSeen ?? (online ? DateTime.now() : prev?.lastSeenAt),
    );
    _scheduleExpiryCheck();
  }

  bool _isFresh(PresenceInfo info) {
    final lastSeen = info.lastSeenAt;
    if (lastSeen == null) return false;
    return DateTime.now().difference(lastSeen) <= _onlineFreshness;
  }

  void _scheduleExpiryCheck() {
    _expiryTimer?.cancel();
    final deadlines = _byUser.values
        .where((info) => info.online && info.lastSeenAt != null)
        .map((info) => info.lastSeenAt!.add(_onlineFreshness))
        .toList();
    if (deadlines.isEmpty) return;
    deadlines.sort();
    final delay = deadlines.first.difference(DateTime.now());
    _expiryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      var changed = false;
      for (final entry in _byUser.entries.toList()) {
        final info = entry.value;
        if (info.online && !_isFresh(info)) {
          _byUser[entry.key] = PresenceInfo(
            userId: info.userId,
            online: false,
            lastSeenAt: info.lastSeenAt,
          );
          changed = true;
        }
      }
      if (changed) notifyListeners();
      if (_byUser.values.any((info) => info.online && info.lastSeenAt != null)) {
        _scheduleExpiryCheck();
      }
    });
  }

  void clear() {
    _byUser.clear();
    _expiryTimer?.cancel();
    _expiryTimer = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    super.dispose();
  }
}
