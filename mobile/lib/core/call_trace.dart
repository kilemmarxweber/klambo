import "dart:convert";

/// Trace d'appel stockée en `__CALL__:{json}` dans le body du message.
class CallTraceInfo {
  const CallTraceInfo({
    required this.kind,
    required this.status,
    this.endReason,
    this.durationMs = 0,
  });

  final String kind;
  final String status;
  final String? endReason;
  final int durationMs;

  bool get isVideo => kind.toUpperCase() == "VIDEO";

  String get label {
    final base = isVideo ? "Appel vidéo" : "Appel audio";
    if (status == "REJECTED") return "$base · refusé";
    if (status == "MISSED" || endReason == "missed") return "$base · manqué";
    if (endReason == "cancelled" ||
        (endReason == "hangup" && durationMs == 0 && status == "ENDED")) {
      return "$base · annulé";
    }
    if (durationMs > 0) {
      final total = (durationMs / 1000).round();
      final m = total ~/ 60;
      final s = total % 60;
      return "$base · $m:${s.toString().padLeft(2, '0')}";
    }
    return base;
  }

  bool get isMissedLike =>
      status == "MISSED" ||
      status == "REJECTED" ||
      endReason == "missed" ||
      endReason == "cancelled";

  static CallTraceInfo? tryParse(String? body) {
    if (body == null) return null;
    final trimmed = body.trim();
    const prefix = "__CALL__:";
    if (!trimmed.startsWith(prefix)) return null;
    try {
      final raw = jsonDecode(trimmed.substring(prefix.length));
      if (raw is! Map) return null;
      return CallTraceInfo(
        kind: raw["kind"]?.toString() ?? "AUDIO",
        status: raw["status"]?.toString() ?? "ENDED",
        endReason: raw["endReason"]?.toString(),
        durationMs: (raw["durationMs"] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}
