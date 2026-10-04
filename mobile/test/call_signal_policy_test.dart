import "package:flutter_test/flutter_test.dart";
import "package:klambo_messagerie/features/calls/call_signal_policy.dart";

void main() {
  test("ICE REST seulement si le socket est coupé", () {
    expect(persistIceOnRest(socketConnected: true), isFalse);
    expect(persistIceOnRest(socketConnected: false), isTrue);
  });

  test("pas de sondage tant que le WebSocket est vivant", () {
    expect(shouldPollCalls(socketConnected: true), isFalse);
    expect(shouldPollCalls(socketConnected: false), isTrue);
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
