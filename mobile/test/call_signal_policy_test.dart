import "package:flutter_test/flutter_test.dart";
import "package:klambo_messagerie/features/calls/call_signal_policy.dart";

void main() {
  test("les candidats publics passent aussi en REST", () {
    const host = "candidate:1 1 UDP 1 192.168.1.2 9 typ host";
    const srflx = "candidate:1 1 UDP 1 1.2.3.4 9 typ srflx";
    const relay = "candidate:1 1 UDP 1 5.6.7.8 9 typ relay";
    expect(
      persistIceOnRest(socketConnected: true, candidate: host),
      isFalse,
    );
    expect(
      persistIceOnRest(socketConnected: true, candidate: srflx),
      isTrue,
    );
    expect(
      persistIceOnRest(socketConnected: true, candidate: relay),
      isTrue,
    );
    expect(
      persistIceOnRest(socketConnected: false, candidate: host),
      isTrue,
    );
    expect(isPublicIceCandidate(srflx), isTrue);
    expect(isPublicIceCandidate(host), isFalse);
  });

  test("pas de sondage tant que le WebSocket est vivant", () {
    expect(shouldPollCalls(socketConnected: true), isFalse);
    expect(shouldPollCalls(socketConnected: false), isTrue);
    expect(
      callFallbackDelay(socketConnected: true, inCall: false),
      isNull,
    );
    expect(
      callFallbackDelay(socketConnected: true, inCall: true),
      isNull,
    );
    expect(
      callFallbackDelay(socketConnected: false, inCall: true),
      const Duration(seconds: 3),
    );
    expect(
      callFallbackDelay(socketConnected: false, inCall: false),
      const Duration(seconds: 15),
    );
  });

  test("un appel terminé côté serveur doit couper l'autre téléphone", () {
    expect(remoteCallFinished("ENDED"), isTrue);
    expect(remoteCallFinished("REJECTED"), isTrue);
    expect(remoteCallFinished("MISSED"), isTrue);
    expect(remoteCallFinished("ACTIVE"), isFalse);
    expect(remoteCallFinished("RINGING"), isFalse);
    expect(remoteCallFinished(null), isFalse);
  });

  test("décrocher depuis la notif attend que l'appel sonne", () {
    expect(
      shouldAutoAcceptNative(requested: true, ringingIn: true),
      isTrue,
    );
    expect(
      shouldAutoAcceptNative(requested: true, ringingIn: false),
      isFalse,
    );
    expect(
      shouldAutoAcceptNative(requested: false, ringingIn: true),
      isFalse,
    );
  });

  test("l'offre n'est plus renvoyée après accusé", () {
    expect(
      shouldResendOffer(acked: false, ringingOut: true),
      isTrue,
    );
    expect(
      shouldResendOffer(acked: true, ringingOut: true),
      isFalse,
    );
    expect(
      shouldResendOffer(acked: false, ringingOut: false),
      isFalse,
    );
  });
}
