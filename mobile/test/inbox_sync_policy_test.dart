import "package:flutter_test/flutter_test.dart";
import "package:klambo_messagerie/features/conversations/inbox_sync_policy.dart";

void main() {
  test("filet inbox + fil même si le socket est vivant", () {
    expect(shouldPollInbox(socketConnected: true), isTrue);
    expect(shouldPollInbox(socketConnected: false), isTrue);
    expect(shouldPollPresence(socketConnected: true), isFalse);
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
    expect((items.single["lastMessage"] as Map)["senderName"], "Awa");
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

  test("merge garde le non-lu WS si le GET serveur est en retard", () {
    final current = <Map<String, dynamic>>[
      {
        "id": "c1",
        "updatedAt": "2026-04-01T00:00:00.000Z",
        "unreadCount": 3,
        "lastMessage": {"id": "m3", "body": "c"},
      },
    ];
    mergeInboxItems(current, [
      {
        "id": "c1",
        "updatedAt": "2026-04-01T00:00:01.000Z",
        "unreadCount": 1,
        "lastMessage": {"id": "m3", "body": "c"},
      },
    ]);
    expect(current.single["unreadCount"], 3);
  });

  test("refresh ne remet pas le non-lu à 0 sans ouverture", () {
    final current = <Map<String, dynamic>>[
      {
        "id": "c1",
        "unreadCount": 4,
        "lastMessage": {"id": "m4", "body": "x"},
      },
    ];
    // GET / cache qui renvoie 0 à tort — on garde 4.
    mergeInboxItems(current, [
      {
        "id": "c1",
        "unreadCount": 0,
        "lastMessage": {"id": "m4", "body": "x"},
      },
    ]);
    expect(current.single["unreadCount"], 4);

    final full = <Map<String, dynamic>>[
      {
        "id": "c1",
        "unreadCount": 0,
        "lastMessage": {"id": "m4", "body": "x"},
      },
    ];
    preserveUnreadOnRefresh(
      incoming: full,
      previous: <Map<String, dynamic>>[
        {
          "id": "c1",
          "unreadCount": 4,
          "lastMessage": {"id": "m4", "body": "x"},
        },
      ],
    );
    expect(full.single["unreadCount"], 4);
  });

  test("grace après ouverture : 0 un court instant si même dernier message", () {
    final now = DateTime.utc(2026, 5, 1, 12);
    final current = <Map<String, dynamic>>[
      {
        "id": "c1",
        "unreadCount": 0,
        "lastMessage": {"id": "m1", "body": "vu"},
      },
    ];
    mergeInboxItems(
      current,
      [
        {
          "id": "c1",
          "unreadCount": 2,
          "lastMessage": {"id": "m1", "body": "vu"},
        },
      ],
      locallyReadAt: {"c1": now.subtract(const Duration(seconds: 2))},
      now: now,
    );
    expect(current.single["unreadCount"], 0);
  });

  test("après la grace, le serveur non-lu revient", () {
    final now = DateTime.utc(2026, 5, 1, 12);
    expect(
      reconcileUnreadCount(
        local: {
          "unreadCount": 0,
          "lastMessage": {"id": "m1"},
        },
        server: {
          "unreadCount": 2,
          "lastMessage": {"id": "m1"},
        },
        locallyReadAt: now.subtract(const Duration(seconds: 30)),
        now: now,
      ),
      2,
    );
  });

  test("event dupliqué n'incrémente pas deux fois le non-lu", () {
    final items = <Map<String, dynamic>>[
      {
        "id": "c1",
        "unreadCount": 0,
        "lastMessage": {"id": "m1", "body": "a"},
      },
    ];
    final event = {
      "type": "message.created",
      "conversationId": "c1",
      "messageId": "m2",
      "senderId": "peer",
      "bodyPreview": "b",
    };
    applyInboxEvent(
      items: items,
      event: event,
      myUserId: "me",
      openConversationId: null,
      now: DateTime.utc(2026, 2, 1),
    );
    expect(items.single["unreadCount"], 1);
    applyInboxEvent(
      items: items,
      event: event,
      myUserId: "me",
      openConversationId: null,
      now: DateTime.utc(2026, 2, 1, 0, 0, 1),
    );
    expect(items.single["unreadCount"], 1);
  });
}
