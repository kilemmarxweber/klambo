import "package:flutter_test/flutter_test.dart";
import "package:klambo_messagerie/features/conversations/inbox_sync_policy.dart";

void main() {
  test("pas de relecture inbox tant que le socket est vivant", () {
    expect(shouldPollInbox(socketConnected: true), isFalse);
    expect(shouldPollPresence(socketConnected: true), isFalse);
    expect(shouldPollInbox(socketConnected: false), isTrue);
    // Fil ouvert : filet HTTP même si WS up (évite message fantôme ~20 s).
    expect(shouldPollThread(socketConnected: true), isTrue);
    expect(shouldPollThread(socketConnected: false), isTrue);
    expect(shouldCatchUpOnLink(inboxPrimed: false), isFalse);
    expect(shouldCatchUpOnLink(inboxPrimed: true), isTrue);
  });

  test("un message nouveau met à jour la ligne sans recharger l'historique", () {
    final items = <Map<String, dynamic>>[
      {
        "id": "c1",
        "updatedAt": "2026-01-01T00:00:00.000Z",
        "unreadCount": 0,
        "lastMessage": {"id": "old", "body": "avant"},
      },
    ];
    final effect = applyInboxEvent(
      items: items,
      event: {
        "type": "message.created",
        "conversationId": "c1",
        "messageId": "m2",
        "senderId": "peer",
        "bodyPreview": "salut",
        "senderName": "Awa",
      },
      myUserId: "me",
      openConversationId: null,
      now: DateTime.utc(2026, 2, 1),
    );
    expect(effect, InboxEventEffect.patched);
    expect(items.single["unreadCount"], 1);
    expect((items.single["lastMessage"] as Map)["body"], "salut");
    expect(items.single["id"], "c1");
  });

  test("mon message et le fil ouvert n'incrémentent pas le non-lu", () {
    final items = <Map<String, dynamic>>[
      {"id": "c1", "unreadCount": 2, "updatedAt": "2026-01-01T00:00:00.000Z"},
    ];
    applyInboxEvent(
      items: items,
      event: {
        "type": "message.created",
        "conversationId": "c1",
        "messageId": "m3",
        "senderId": "me",
        "bodyPreview": "ok",
      },
      myUserId: "me",
      openConversationId: null,
      now: DateTime.utc(2026, 2, 1),
    );
    expect(items.single["unreadCount"], 2);

    applyInboxEvent(
      items: items,
      event: {
        "type": "message.created",
        "conversationId": "c1",
        "messageId": "m4",
        "senderId": "peer",
        "bodyPreview": "vu",
      },
      myUserId: "me",
      openConversationId: "c1",
      now: DateTime.utc(2026, 2, 2),
    );
    expect(items.single["unreadCount"], 0);
  });

  test("conversation inconnue ou appel : pas de rafale HTTP", () {
    final items = <Map<String, dynamic>>[];
    expect(
      applyInboxEvent(
        items: items,
        event: {
          "type": "message.created",
          "conversationId": "new",
          "senderId": "peer",
        },
        myUserId: "me",
        openConversationId: null,
        now: DateTime.utc(2026, 2, 1),
      ),
      InboxEventEffect.catchUp,
    );
    expect(
      applyInboxEvent(
        items: items,
        event: {"type": "call.offer", "conversationId": "c1"},
        myUserId: "me",
        openConversationId: null,
        now: DateTime.utc(2026, 2, 1),
      ),
      InboxEventEffect.ignored,
    );
  });

  test("le delta remplace la ligne et garde le plus récent en tête", () {
    final current = <Map<String, dynamic>>[
      {"id": "old", "updatedAt": "2026-01-01T00:00:00.000Z"},
      {"id": "keep", "updatedAt": "2026-03-01T00:00:00.000Z"},
    ];
    mergeInboxItems(current, [
      {"id": "old", "updatedAt": "2026-04-01T00:00:00.000Z", "unreadCount": 1},
    ]);
    expect(current.map((e) => e["id"]), ["old", "keep"]);
    expect(inboxWatermark(current), "2026-04-01T00:00:00.000Z");
  });
}
