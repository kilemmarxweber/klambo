import "dart:convert";

/// Trace d'appel stockée en `__CALL__:{json}` dans le body du message.
class CallTraceInfo {
  const CallTraceInfo({
    required this.kind,
    required this.status,
    this.endReason,
    this.durationMs = 0,
    this.callId,
  });

  final String kind;
  final String status;
  final String? endReason;
  final int durationMs;
  final String? callId;

  static const bodyPrefix = "__CALL__:";

  bool get isVideo => kind.toUpperCase() == "VIDEO";

  String get _kindLabel => isVideo ? "Appel vidéo" : "Appel vocal";

  bool get _cancelled =>
      endReason == "cancelled" ||
      (endReason == "hangup" && durationMs == 0 && status == "ENDED");

  /// Titre de la carte dans la bulle.
  String get headline {
    if (status == "REJECTED") return "$_kindLabel refusé";
    if (status == "MISSED" || endReason == "missed") return "$_kindLabel manqué";
    if (_cancelled) return "$_kindLabel annulé";
    return _kindLabel;
  }

  /// Ligne sous le titre : rappel, ou durée.
  String get caption {
    if (isMissedLike || durationMs <= 0) return "Appuyez pour rappeler";
    final total = (durationMs / 1000).round();
    final m = total ~/ 60;
    final s = total % 60;
    if (m <= 0) return "$s s";
    return "$m min ${s.toString().padLeft(2, "0")} s";
  }

  String get label => statusLabel(
        kind: kind,
        status: status,
        endReason: endReason,
        durationMs: durationMs,
      );

  /// Libellé clair pour tout statut d'appel (notif / liste / badge).
  static String statusLabel({
    required String kind,
    required String status,
    String? endReason,
    int durationMs = 0,
  }) {
    final video = kind.toUpperCase() == "VIDEO";
    final base = video ? "Appel vidéo" : "Appel audio";
    final reason = (endReason ?? "").trim().toLowerCase();
    final st = status.trim().toUpperCase();
    if (st == "REJECTED" ||
        reason == "rejected" ||
        reason == "reject" ||
        reason == "busy") {
      return "$base · refusé";
    }
    if (st == "MISSED" || reason == "missed") return "$base · manqué";
    if (st == "RINGING" || st == "OFFER" || st == "INCOMING") {
      return video ? "Appel vidéo entrant" : "Appel audio entrant";
    }
    final cancelled = reason == "cancelled" ||
        (reason == "hangup" && durationMs == 0 && st == "ENDED");
    if (cancelled) return "$base · annulé";
    if (durationMs > 0) {
      final total = (durationMs / 1000).round();
      final m = total ~/ 60;
      final s = total % 60;
      return "$base · $m:${s.toString().padLeft(2, '0')}";
    }
    if (st == "ENDED" || st == "HANGUP" || reason == "hangup") {
      return "$base · terminé";
    }
    return base;
  }

  /// Texte notif / liste / badge — **jamais** le JSON `__CALL__:…`.
  static String previewOf(String? raw, {String fallback = "Appel"}) {
    final parsed = tryParse(raw);
    if (parsed != null) return parsed.label;
    final trimmed = raw?.trim() ?? "";
    if (trimmed.isEmpty) return fallback;
    // Tronqué / JSON partiel : extraire kind/status si possible.
    if (looksLikeCallTrace(trimmed)) {
      return _labelFromPartial(trimmed) ?? fallback;
    }
    return trimmed;
  }

  /// True si le texte est (ou commence comme) une trace `__CALL__` / JSON d'appel.
  static bool looksLikeCallTrace(String? raw) {
    final t = raw?.trim() ?? "";
    if (t.isEmpty) return false;
    if (t.startsWith(bodyPrefix)) return true;
    if (t.startsWith("{") &&
        (t.contains('"kind"') || t.contains('"callId"')) &&
        (t.contains('"status"') || t.contains('"endReason"'))) {
      return true;
    }
    return false;
  }

  static String? _labelFromPartial(String raw) {
    final src = raw.startsWith(bodyPrefix)
        ? raw.substring(bodyPrefix.length)
        : raw;
    String? field(String key) {
      final m = RegExp(
        '"$key"\\s*:\\s*"([^"]*)"',
        caseSensitive: false,
      ).firstMatch(src);
      return m?.group(1);
    }

    int duration() {
      final m = RegExp(
        r'"durationMs"\s*:\s*(\d+)',
        caseSensitive: false,
      ).firstMatch(src);
      return int.tryParse(m?.group(1) ?? "") ?? 0;
    }

    final kind = field("kind") ?? "AUDIO";
    final status = field("status") ?? "ENDED";
    final endReason = field("endReason");
    if (field("kind") == null &&
        field("status") == null &&
        field("endReason") == null) {
      return null;
    }
    return statusLabel(
      kind: kind,
      status: status,
      endReason: endReason,
      durationMs: duration(),
    );
  }

  bool get isMissedLike =>
      status == "MISSED" ||
      status == "REJECTED" ||
      endReason == "missed" ||
      endReason == "cancelled";

  /// Sérialise pour insertion immédiate dans le fil.
  String toBody() {
    final map = <String, dynamic>{
      "kind": kind,
      "status": status,
      "durationMs": durationMs,
    };
    if (endReason != null) map["endReason"] = endReason;
    if (callId != null && callId!.isNotEmpty) map["callId"] = callId;
    return "$bodyPrefix${jsonEncode(map)}";
  }

  /// Mappe la fin d'appel locale → statut affiché (reçu / manqué / raccroché).
  static CallTraceInfo fromCallEnd({
    required String kind,
    required bool isCaller,
    required bool wasAnswered,
    required String? reason,
    required int durationMs,
    String? callId,
  }) {
    final r = (reason ?? "")
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r"^call\."), "");
    final safeDuration = durationMs < 0 ? 0 : durationMs;

    if (r == "rejected" || r == "reject" || r == "busy") {
      return CallTraceInfo(
        kind: kind,
        status: "REJECTED",
        endReason: r == "busy" ? "busy" : "rejected",
        durationMs: 0,
        callId: callId,
      );
    }

    if (!wasAnswered || safeDuration <= 0) {
      // Pas de conversation média : manqué / annulé.
      if (isCaller && (r == "hangup" || r == "cancelled")) {
        return CallTraceInfo(
          kind: kind,
          status: "ENDED",
          endReason: "cancelled",
          durationMs: 0,
          callId: callId,
        );
      }
      return CallTraceInfo(
        kind: kind,
        status: "MISSED",
        endReason: "missed",
        durationMs: 0,
        callId: callId,
      );
    }

    return CallTraceInfo(
      kind: kind,
      status: "ENDED",
      endReason: r.isEmpty ? "hangup" : r,
      durationMs: safeDuration,
      callId: callId,
    );
  }

  static CallTraceInfo? tryParse(String? body) {
    if (body == null) return null;
    final trimmed = body.trim();
    if (!trimmed.startsWith(bodyPrefix)) return null;
    try {
      final raw = jsonDecode(trimmed.substring(bodyPrefix.length));
      if (raw is! Map) return null;
      return CallTraceInfo(
        kind: raw["kind"]?.toString() ?? "AUDIO",
        status: raw["status"]?.toString() ?? "ENDED",
        endReason: raw["endReason"]?.toString(),
        durationMs: (raw["durationMs"] as num?)?.toInt() ?? 0,
        callId: raw["callId"]?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}
