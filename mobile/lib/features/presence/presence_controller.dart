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
  final Map<String, PresenceInfo> _byUser = {};
  String? _organizationId;

  /// Présence distante visible seulement si le réseau et le WebSocket sont actifs.
  bool _networkUp = true;
  bool _socketUp = false;

  String? get organizationId => _organizationId;

  bool get linkUp => _networkUp && _socketUp;

  PresenceInfo? of(String userId) {
    final info = _byUser[userId];
    if (info == null) return null;
    if (!linkUp && info.online) {
      return info.copyWith(online: false);
    }
    return info;
  }

  bool isOnline(String userId) => linkUp && _byUser[userId]?.online == true;

  DateTime? lastSeenAt(String userId) => _byUser[userId]?.lastSeenAt;

  /// Appelé quand le WebSocket local tombe / revient.
  void setLinkUp(bool up) {
    _updateLink(socketUp: up);
  }

  /// Un réseau absent masque immédiatement la présence; le retour du réseau
  /// seul ne la réactive pas tant que le WebSocket n'est pas reconnecté.
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
  }

  void clear() {
    _byUser.clear();
    notifyListeners();
  }
}
