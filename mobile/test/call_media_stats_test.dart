import "package:flutter_test/flutter_test.dart";
import "package:klambo_messagerie/features/calls/call_media_stats.dart";

void main() {
  test("détecte un appel relayé TURN et le RTT", () {
    final snap = parseCallStats([
      {
        "id": "pair1",
        "type": "candidate-pair",
        "values": {
          "nominated": true,
          "state": "succeeded",
          "localCandidateId": "local1",
          "currentRoundTripTime": 0.08,
        },
      },
      {
        "id": "local1",
        "type": "local-candidate",
        "values": {"candidateType": "relay"},
      },
      {
        "type": "inbound-rtp",
        "values": {
          "kind": "video",
          "packetsLost": 4,
          "packetsReceived": 96,
        },
      },
    ]);
    expect(snap.path, "relay");
    expect(snap.packetsLost, 4);
    expect(snap.rttMs, closeTo(80, 0.01));
  });

  test("baisse puis remonte le bitrate vidéo selon la perte", () {
    final down = nextVideoBitrate(
      current: 900000,
      deltaLost: 20,
      deltaReceived: 80,
      rttMs: 50,
    );
    expect(down, 450000);
    final up = nextVideoBitrate(
      current: 450000,
      deltaLost: 0,
      deltaReceived: 100,
      rttMs: 40,
    );
    expect(up, 900000);
    final floor = nextVideoBitrate(
      current: 180000,
      deltaLost: 30,
      deltaReceived: 20,
      rttMs: 500,
    );
    expect(floor, 180000);
  });
}
