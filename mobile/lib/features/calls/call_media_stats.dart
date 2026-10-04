class CallMediaSnapshot {
  const CallMediaSnapshot({
    required this.path,
    required this.packetsLost,
    required this.packetsReceived,
    required this.rttMs,
  });

  /// host, srflx, relay ou unknown.
  final String path;
  final int packetsLost;
  final int packetsReceived;
  final double? rttMs;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? "") ?? 0;
}

double? _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? "");
}

Map<String, dynamic> _values(Map<String, dynamic> report) {
  final raw = report["values"];
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return report;
}

/// Lit les stats WebRTC déjà normalisées (`type` + `values`).
CallMediaSnapshot parseCallStats(List<Map<String, dynamic>> reports) {
  String? localId;
  String? remoteId;
  double? rttSeconds;
  var lost = 0;
  var received = 0;

  for (final report in reports) {
    final type = report["type"]?.toString() ?? "";
    final values = _values(report);
    if (type == "inbound-rtp") {
      final kind = values["kind"]?.toString() ?? values["mediaType"]?.toString();
      if (kind == "video" || kind == null || kind.isEmpty) {
        lost += _asInt(values["packetsLost"]);
        received += _asInt(values["packetsReceived"]);
      }
    }
    final nominated = values["nominated"] == true || values["nominated"] == "true";
    final selected = values["selected"] == true || values["state"] == "succeeded";
    if (type == "candidate-pair" && (nominated || selected) && localId == null) {
      localId = values["localCandidateId"]?.toString();
      remoteId = values["remoteCandidateId"]?.toString();
      rttSeconds = _asDouble(
        values["currentRoundTripTime"] ?? values["roundTripTime"],
      );
    }
  }

  var path = "unknown";
  for (final report in reports) {
    final type = report["type"]?.toString() ?? "";
    if (type != "local-candidate" && type != "remote-candidate") continue;
    final values = _values(report);
    final id = report["id"]?.toString() ?? values["id"]?.toString();
    if (id == null) continue;
    if (id != localId && id != remoteId) continue;
    final candidateType =
        (values["candidateType"] ?? values["candidateTypetype"])?.toString();
    if (candidateType == "relay") {
      path = "relay";
      break;
    }
    if (candidateType == "srflx" && path != "relay") path = "srflx";
    if (candidateType == "host" && path == "unknown") path = "host";
  }

  return CallMediaSnapshot(
    path: path,
    packetsLost: lost,
    packetsReceived: received,
    rttMs: rttSeconds == null ? null : rttSeconds * 1000,
  );
}

const videoBitrateSteps = [180000, 450000, 900000];

int nextVideoBitrate({
  required int current,
  required int deltaLost,
  required int deltaReceived,
  required double? rttMs,
}) {
  var index = videoBitrateSteps.indexOf(current);
  if (index < 0) index = videoBitrateSteps.length - 1;
  final total = deltaLost + deltaReceived;
  if (total < 20) return videoBitrateSteps[index];
  final loss = deltaLost <= 0 ? 0.0 : deltaLost / total;
  if (loss > 0.08 || (rttMs != null && rttMs > 400)) {
    index = (index - 1).clamp(0, videoBitrateSteps.length - 1);
  } else if (loss < 0.01 && (rttMs == null || rttMs < 180)) {
    index = (index + 1).clamp(0, videoBitrateSteps.length - 1);
  }
  return videoBitrateSteps[index];
}
