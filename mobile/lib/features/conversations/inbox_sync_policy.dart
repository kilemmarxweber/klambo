import "package:klambo_messagerie/core/call_trace.dart";

/// Liste et fil : une lecture complète, puis l'écoute.
///
/// Même filet que le fil ouvert : le WS peut être « up » sans Redis, donc
/// sans `message.created`. HTTP `since` rattrape la liste comme le chat.
bool shouldPollInbox({required bool socketConnected}) => true;

/// Secours HTTP du fil : toujours utile (cache WS raté), plus fréquent si WS down.
bool shouldPollThread({required bool socketConnected}) => true;

/// Intervalle de rattrapage quand le socket est vivant (filet léger).
const threadCatchUpInterval = Duration(seconds: 12);

bool shouldPollPresence({required bool socketConnected}) => !socketConnected;

/// Aligné sur le fil : aperçu / badge à jour sans attendre 45 s.
const inboxFallbackInterval = Duration(seconds: 12);
const threadFallbackInterval = Duration(seconds: 30);
const presenceFallbackInterval = Duration(seconds: 60);

/// Après ouverture : on ignore un stale serveur « encore non lu » un court instant.
const locallyReadGrace = Duration(seconds: 12);

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
  final newMessageId = event["messageId"]?.toString();
  final prevLast = item["lastMessage"];
  final prevMessageId =
      prevLast is Map ? prevLast["id"]?.toString() : null;
  // Même event rejoué (WS + publishLocal) → ne pas recompter.
  final duplicate = newMessageId != null &&
      newMessageId.isNotEmpty &&
      newMessageId == prevMessageId;

  item["updatedAt"] = at;
  final cipher = event["bodyCipher"]?.toString() ?? "";
  final rawPreview = cipher.startsWith("k1.")
      ? cipher
      : (event["bodyPreview"]?.toString() ??
          event["body"]?.toString() ??
          "");
  // Aperçu liste / badge : libellé d'appel clair, jamais __CALL__:{…}.
  final previewBody = _humanizeInboxPreview(rawPreview);
  item["lastMessage"] = {
    "id": event["messageId"],
    "body": previewBody,
    "senderId": senderId,
    "senderName": event["senderName"],
    "senderImage": event["senderImage"],
    "createdAt": at,
  };
  final mine = senderId != null && senderId == myUserId;
  final open = openConversationId != null && openConversationId == convId;
  if (open) {
    item["unreadCount"] = 0;
  } else if (!mine && !duplicate) {
    item["unreadCount"] = _unread(item) + 1;
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
  List<Map<String, dynamic>> incoming, {
  Map<String, DateTime> locallyReadAt = const {},
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  for (final raw in incoming) {
    final id = raw["id"]?.toString();
    if (id == null || id.isEmpty) continue;
    final idx = current.indexWhere((item) => item["id"]?.toString() == id);
    final server = Map<String, dynamic>.from(raw);
    if (idx >= 0) {
      final local = current[idx];
      server["unreadCount"] = reconcileUnreadCount(
        local: local,
        server: server,
        locallyReadAt: locallyReadAt[id],
        now: clock,
      );
      current.removeAt(idx);
    }
    current.add(server);
  }
  current.sort((a, b) {
    final aAt = a["updatedAt"]?.toString() ?? "";
    final bAt = b["updatedAt"]?.toString() ?? "";
    return bAt.compareTo(aAt);
  });
}

/// Préserve le non-lu au refresh : on ne remet jamais à 0 sans ouverture.
///
/// - WS en avance sur le GET → garde le max local
/// - GET plus haut → prend le serveur
/// - Grace courte après ouverture seulement
int reconcileUnreadCount({
  required Map<String, dynamic> local,
  required Map<String, dynamic> server,
  DateTime? locallyReadAt,
  DateTime? now,
}) {
  final localUnread = _unread(local);
  final serverUnread = _unread(server);
  final localLast = local["lastMessage"];
  final serverLast = server["lastMessage"];
  final localLastId =
      localLast is Map ? localLast["id"]?.toString() : null;
  final serverLastId =
      serverLast is Map ? serverLast["id"]?.toString() : null;
  final clock = now ?? DateTime.now();

  if (locallyReadAt != null &&
      clock.difference(locallyReadAt) < locallyReadGrace &&
      localLastId != null &&
      localLastId.isNotEmpty &&
      localLastId == serverLastId) {
    return 0;
  }

  // Refresh / poll : toujours le plus haut des deux (jamais perdre le badge).
  return localUnread > serverUnread ? localUnread : serverUnread;
}

/// Applique [reconcileUnreadCount] sur une liste serveur vs l'état local.
void preserveUnreadOnRefresh({
  required List<Map<String, dynamic>> incoming,
  required List<Map<String, dynamic>> previous,
  Map<String, DateTime> locallyReadAt = const {},
  DateTime? now,
}) {
  if (previous.isEmpty) return;
  final byId = <String, Map<String, dynamic>>{};
  for (final item in previous) {
    final id = item["id"]?.toString();
    if (id == null || id.isEmpty) continue;
    byId[id] = item;
  }
  final clock = now ?? DateTime.now();
  for (var i = 0; i < incoming.length; i++) {
    final id = incoming[i]["id"]?.toString();
    if (id == null) continue;
    final local = byId[id];
    if (local == null) continue;
    final copy = Map<String, dynamic>.from(incoming[i]);
    copy["unreadCount"] = reconcileUnreadCount(
      local: local,
      server: copy,
      locallyReadAt: locallyReadAt[id],
      now: clock,
    );
    incoming[i] = Map<String, dynamic>.from(copy);
  }
}

int _unread(Map<String, dynamic> item) {
  final raw = item["unreadCount"];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? "") ?? 0;
}

String _humanizeInboxPreview(String raw) {
  if (raw.startsWith("k1.")) return raw;
  return CallTraceInfo.previewOf(raw, fallback: raw);
}
