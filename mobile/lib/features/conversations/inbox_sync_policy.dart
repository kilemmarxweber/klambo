/// Liste et fil : une lecture complète, puis l'écoute.
///
/// Le WebSocket porte les messages nouveaux. HTTP ne revient que si le
/// socket est coupé, et alors seulement pour le delta `since`.
bool shouldPollInbox({required bool socketConnected}) => !socketConnected;

bool shouldPollThread({required bool socketConnected}) => !socketConnected;

bool shouldPollPresence({required bool socketConnected}) => !socketConnected;

const inboxFallbackInterval = Duration(seconds: 45);
const threadFallbackInterval = Duration(seconds: 30);
const presenceFallbackInterval = Duration(seconds: 60);

/// Rattrapage `since` au retour du lien, pas un second chargement complet.
bool shouldCatchUpOnLink({required bool inboxPrimed}) => inboxPrimed;

enum InboxEventEffect { ignored, patched, catchUp }

/// Met à jour la liste déjà en mémoire. `catchUp` = conversation inconnue
/// ou message modifié : un seul GET `since`, pas toute l'historique.
InboxEventEffect applyInboxEvent({
  required List<Map<String, dynamic>> items,
  required Map<String, dynamic> event,
  required String? myUserId,
  required String? openConversationId,
  required DateTime now,
}) {
  final type = event["type"]?.toString() ?? "";
  if (type == "link.up" || type == "link.down" || type.startsWith("call.")) {
    return InboxEventEffect.ignored;
  }
  if (type != "message.created" &&
      type != "message.updated" &&
      type != "message.deleted") {
    return InboxEventEffect.ignored;
  }

  final convId = event["conversationId"]?.toString() ?? "";
  if (convId.isEmpty) return InboxEventEffect.catchUp;

  final index = items.indexWhere((item) => item["id"]?.toString() == convId);
  if (index < 0) return InboxEventEffect.catchUp;
  if (type != "message.created") return InboxEventEffect.catchUp;

  final item = Map<String, dynamic>.from(items[index]);
  final at = now.toUtc().toIso8601String();
  final senderId = event["senderId"]?.toString();
  item["updatedAt"] = at;
  final cipher = event["bodyCipher"]?.toString() ?? "";
  item["lastMessage"] = {
    "id": event["messageId"],
    "body": cipher.startsWith("k1.")
        ? cipher
        : (event["bodyPreview"]?.toString() ?? ""),
    "senderId": senderId,
    "senderName": event["senderName"],
    "createdAt": at,
  };
  final mine = senderId != null && senderId == myUserId;
  final open = openConversationId != null && openConversationId == convId;
  if (!mine && !open) {
    item["unreadCount"] = _unread(item) + 1;
  } else if (open) {
    item["unreadCount"] = 0;
  }
  items.removeAt(index);
  items.insert(0, item);
  return InboxEventEffect.patched;
}

String? inboxWatermark(List<Map<String, dynamic>> items) {
  String? max;
  for (final item in items) {
    final at = item["updatedAt"]?.toString();
    if (at == null || at.isEmpty) continue;
    if (max == null || at.compareTo(max) > 0) max = at;
  }
  return max;
}

void mergeInboxItems(
  List<Map<String, dynamic>> current,
  List<Map<String, dynamic>> incoming,
) {
  for (final raw in incoming) {
    final id = raw["id"]?.toString();
    if (id == null || id.isEmpty) continue;
    current.removeWhere((item) => item["id"]?.toString() == id);
    current.add(Map<String, dynamic>.from(raw));
  }
  current.sort((a, b) {
    final aAt = a["updatedAt"]?.toString() ?? "";
    final bAt = b["updatedAt"]?.toString() ?? "";
    return bAt.compareTo(aAt);
  });
}

int _unread(Map<String, dynamic> item) {
  final raw = item["unreadCount"];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? "") ?? 0;
}
