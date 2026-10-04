import "package:flutter_test/flutter_test.dart";
import "package:klambo_messagerie/features/calls/call_link.dart";

void main() {
  test("parseIceSignal distingue disconnected de connected", () {
    expect(
      parseIceSignal("RTCIceConnectionStateDisconnected"),
      CallIceSignal.disconnected,
    );
    expect(
      parseIceSignal("RTCIceConnectionStateConnected"),
      CallIceSignal.connected,
    );
    expect(
      parseIceSignal("RTCPeerConnectionStateFailed"),
      CallIceSignal.failed,
    );
  });

  test("le média n'est actif qu'une fois ICE connecté", () {
    final link = CallLink();
    expect(link.onIce(CallIceSignal.checking), CallLinkAction.none);
    expect(link.mediaUp, isFalse);
    expect(markActiveOnAnswer(mediaAlreadyUp: false), isFalse);
    expect(link.onIce(CallIceSignal.connected), CallLinkAction.mediaUp);
    expect(link.mediaUp, isTrue);
    expect(markActiveOnAnswer(mediaAlreadyUp: true), isTrue);
  });

  test("disconnected attend, failed relance une fois puis abandonne", () {
    final link = CallLink();
    expect(link.onIce(CallIceSignal.disconnected), CallLinkAction.scheduleRestart);
    expect(link.onIce(CallIceSignal.disconnected), CallLinkAction.none);
    expect(link.takeRestart(), CallLinkAction.restartNow);
    expect(link.takeRestart(), CallLinkAction.none);

    link.restartInFlight = false;
    expect(link.onIce(CallIceSignal.failed), CallLinkAction.endFailed);
  });

  test("un succès autorise une nouvelle reprise plus tard", () {
    final link = CallLink();
    expect(link.onIce(CallIceSignal.failed), CallLinkAction.restartNow);
    expect(link.takeRestart(), CallLinkAction.restartNow);
    expect(link.onIce(CallIceSignal.completed), CallLinkAction.mediaUp);
    expect(link.restartAttempts, 0);
    expect(link.onIce(CallIceSignal.disconnected), CallLinkAction.scheduleRestart);
  });

  test("changement de réseau pendant l'appel arme une reprise", () {
    final link = CallLink();
    expect(
      link.onNetworkChanged(mediaPhase: false),
      CallLinkAction.none,
    );
    link.mediaUp = true;
    expect(
      link.onNetworkChanged(mediaPhase: true),
      CallLinkAction.scheduleRestart,
    );
    expect(
      link.onNetworkChanged(mediaPhase: true),
      CallLinkAction.none,
    );
  });

  test("un second appel reçoit occupé, pas le même callId", () {
    expect(shouldReplyBusy(inCall: true, sameCall: false), isTrue);
    expect(shouldReplyBusy(inCall: true, sameCall: true), isFalse);
    expect(shouldReplyBusy(inCall: false, sameCall: false), isFalse);
  });
}
