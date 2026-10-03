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

  String? get organizationId => _organizationId;

  PresenceInfo? of(String userId) => _byUser[userId];

  bool isOnline(String userId) => _byUser[userId]?.online == true;

  DateTime? lastSeenAt(String userId) => _byUser[userId]?.lastSeenAt;

  void setOrganization(String organizationId) {
    if (_organizationId == organizationId) return;
    _organizationId = organizationId;
    // Ne pas vider le cache : évite un flash « hors ligne » pendant le refresh.
    notifyListeners();
  }

  void applyEvent(Map<String, dynamic> event) {
    final type = event["type"]?.toString() ?? "";
    if (type == "presence.snapshot") {
      final items = event["items"];
      if (items is! List) return;
      for (final raw in items) {
        if (raw is! Map) continue;
        _upsert(
          userId: raw["userId"]?.toString(),
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
      userId: event["userId"]?.toString(),
      status: event["status"]?.toString(),
      lastSeenRaw: event["lastSeenAt"]?.toString(),
    );
    notifyListeners();
  }

  void applyRestItems(List<dynamic> items) {
    for (final raw in items) {
      if (raw is! Map) continue;
      _upsert(
        userId: raw["userId"]?.toString(),
        status: raw["status"]?.toString(),
        lastSeenRaw: raw["lastSeenAt"]?.toString(),
        onlineFlag: raw["online"] is bool ? raw["online"] as bool : null,
      );
    }
    notifyListeners();
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
    final online = onlineFlag ?? (status?.toUpperCase() == "ONLINE");
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
