import "package:flutter_test/flutter_test.dart";
import "package:klambo_messagerie/core/notify_trace.dart";

void main() {
  test("NotifyTrace parses school card JSON", () {
    const body =
        '__NOTIFY__:{"v":1,"tone":"rose","title":"Absence","brand":"Collège","intro":"Marie absente","rows":[{"label":"Classe","value":"5e A"},{"label":"Montant","value":"50","kind":"highlight"}],"cta":{"label":"Voir","href":"https://example.com"}}';
    final card = NotifyTrace.tryParse(body);
    expect(card, isNotNull);
    expect(card!.title, "Absence");
    expect(card.tone, "rose");
    expect(card.brand, "Collège");
    expect(card.rows.length, 2);
    expect(card.preview, "Absence · Montant");
    expect(card.ctaLabel, "Voir");
  });

  test("NotifyTrace rejects plain text", () {
    expect(NotifyTrace.tryParse("Bonjour"), isNull);
  });

  test("NotifyTrace suggestsOfficialAck for navy/rose", () {
    const rose =
        '__NOTIFY__:{"v":1,"tone":"rose","title":"Absence"}';
    const amber =
        '__NOTIFY__:{"v":1,"tone":"amber","title":"Rappel paiement"}';
    const officialAmber =
        '__NOTIFY__:{"v":1,"tone":"amber","title":"Avis officiel"}';
    expect(NotifyTrace.tryParse(rose)!.suggestsOfficialAck, isTrue);
    expect(NotifyTrace.tryParse(amber)!.suggestsOfficialAck, isFalse);
    expect(NotifyTrace.tryParse(officialAmber)!.suggestsOfficialAck, isTrue);
  });
}
