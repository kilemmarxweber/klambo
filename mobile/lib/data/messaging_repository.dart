import "dart:typed_data";

import "package:dio/dio.dart";
import "package:http_parser/http_parser.dart";
import "package:klambo_messagerie/data/api_client.dart";
import "package:klambo_messagerie/data/message_cache.dart";
import "package:klambo_messagerie/features/crypto/message_vault.dart";

class MessagingRepository {
  MessagingRepository(this._api, {MessageCache? cache, MessageVault? vault})
      : _cache = cache ?? MessageCache(),
        _vault = vault ?? MessageVault(api: _api);

  final ApiClient _api;
  final MessageCache _cache;
  final MessageVault _vault;

  Future<void> ensureMessageKeys() => _vault.ensureRegistered();

  Future<String> openBody(String body) => _vault.open(body);

  Future<String> _seal(String body, String? peerUserId) {
    if (peerUserId == null || peerUserId.isEmpty || body.trim().isEmpty) {
      return Future.value(body);
    }
    return _vault.seal(body, peerUserId: peerUserId);
  }

  Future<void> _revealBody(Map<String, dynamic> item) async {
    final raw = item["body"];
    if (raw is! String || raw.isEmpty) return;
    item["body"] = await _vault.open(raw);
  }

  Future<List<Map<String, dynamic>>> _revealMessages(List items) async {
    final out = <Map<String, dynamic>>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      await _revealBody(item);
      final reply = item["replyTo"];
      if (reply is Map) {
        final copy = Map<String, dynamic>.from(reply);
        await _revealBody(copy);
        item["replyTo"] = copy;
      }
      out.add(item);
    }
    return out;
  }

  Future<void> _revealConversations(List<Map<String, dynamic>> items) async {
    for (final item in items) {
      final last = item["lastMessage"];
      if (last is! Map) continue;
      final copy = Map<String, dynamic>.from(last);
      await _revealBody(copy);
      item["lastMessage"] = copy;
    }
  }

  /// Résultat éventuellement servi depuis le cache local.
  Future<Map<String, dynamic>> listConversations(
    String organizationId, {
    String filter = "all",
    String? cursor,
    String? since,
  }) async {
    final delta = since != null && since.isNotEmpty;
    try {
      final data = await _api.getJson(
        "/organizations/$organizationId/conversations",
        query: {
          "filter": filter,
          if (cursor != null) "cursor": cursor,
          if (delta) "since": since,
        },
      );
      final items = (data["items"] as List?) ?? [];
      final mapped = items
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      await _revealConversations(mapped);
      // Un delta ne remplace pas le cache de toute la liste.
      if (!delta) await _cache.saveConversations(organizationId, mapped);
      return {...data, "items": mapped, "fromCache": false};
    } catch (e) {
      final cached = await _cache.getConversations(organizationId);
      if (cached != null) {
        final mapped = cached
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        await _revealConversations(mapped);
        return {"items": mapped, "fromCache": true};
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> listMessages(
    String organizationId,
    String conversationId, {
    String? cursor,
  }) async {
    try {
      final data = await _api.getJson(
        "/organizations/$organizationId/conversations/$conversationId/messages",
        query: {if (cursor != null) "cursor": cursor},
      );
      final items = (data["items"] as List?) ?? [];
      final revealed = await _revealMessages(items);
      await _cache.saveMessages(organizationId, conversationId, revealed);
      return {...data, "items": revealed, "fromCache": false};
    } catch (e) {
      final cached = await _cache.getMessages(organizationId, conversationId);
      if (cached != null) {
        final revealed = await _revealMessages(cached);
        return {"items": revealed, "fromCache": true};
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> sendMessage(
    String organizationId,
    String conversationId, {
    required String body,
    String? replyToId,
    String? clientMessageId,
    String? peerUserId,
  }) async {
    final sealed = await _seal(body, peerUserId);
    return _api.postJson(
      "/organizations/$organizationId/conversations/$conversationId/messages",
      data: {
        "body": sealed,
        if (replyToId != null) "replyToId": replyToId,
        if (clientMessageId != null) "clientMessageId": clientMessageId,
      },
    );
  }

  Future<Map<String, dynamic>> editMessage(
    String organizationId,
    String conversationId,
    String messageId, {
    required String body,
    String? peerUserId,
  }) async {
    final sealed = await _seal(body, peerUserId);
    return _api.patchJson(
      "/organizations/$organizationId/conversations/$conversationId/messages/$messageId",
      data: {"body": sealed},
    );
  }

  Future<Map<String, dynamic>> deleteMessage(
    String organizationId,
    String conversationId,
    String messageId,
  ) {
    return _api.deleteJson(
      "/organizations/$organizationId/conversations/$conversationId/messages/$messageId",
    );
  }

  MediaType _mediaType(String filename, String? mime) {
    if (mime != null && mime.contains("/")) {
      final parts = mime.split("/");
      return MediaType(parts[0], parts[1]);
    }
    final lower = filename.toLowerCase();
    if (lower.endsWith(".png")) return MediaType("image", "png");
    if (lower.endsWith(".webp")) return MediaType("image", "webp");
    if (lower.endsWith(".gif")) return MediaType("image", "gif");
    if (lower.endsWith(".pdf")) return MediaType("application", "pdf");
    if (lower.endsWith(".mp3")) return MediaType("audio", "mpeg");
    if (lower.endsWith(".m4a")) return MediaType("audio", "mp4");
    if (lower.endsWith(".aac")) return MediaType("audio", "aac");
    if (lower.endsWith(".wav")) return MediaType("audio", "wav");
    if (lower.endsWith(".ogg")) return MediaType("audio", "ogg");
    if (lower.endsWith(".webm")) return MediaType("audio", "webm");
    if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) {
      return MediaType("image", "jpeg");
    }
    return MediaType("application", "octet-stream");
  }

  /// Envoie un message avec pièce jointe (image, PDF, audio…).
  Future<Map<String, dynamic>> sendMediaMessage(
    String organizationId,
    String conversationId, {
    required Uint8List bytes,
    required String filename,
    String? mimeType,
    String body = "",
    String? clientMessageId,
    int? durationMs,
    String? peerUserId,
  }) async {
    try {
      final sealed = await _seal(body, peerUserId);
      final form = FormData.fromMap({
        if (sealed.trim().isNotEmpty) "body": sealed.trim(),
        if (clientMessageId != null) "clientMessageId": clientMessageId,
        if (durationMs != null && durationMs > 0)
          "durationMs": durationMs.toString(),
        "file": MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: _mediaType(filename, mimeType),
        ),
      });
      final res = await _api.dio.post(
        "/organizations/$organizationId/conversations/$conversationId/media",
        data: form,
      );
      final raw = res.data;
      if (raw is! Map) throw Exception("Réponse média invalide");
      if (raw["ok"] == false) {
        throw Exception(raw["error"]?.toString() ?? "Upload média échoué");
      }
      final data = raw["data"];
      if (data is Map) return Map<String, dynamic>.from(data);
      return Map<String, dynamic>.from(raw);
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? e.response!.data["error"]?.toString()
          : null;
      throw Exception(msg ?? e.message ?? "Upload média échoué");
    }
  }

  Future<Map<String, dynamic>> createConversation(
    String organizationId, {
    required List<String> recipientIds,
    required String body,
    String? subject,
    bool asGroup = false,
    String? clientMessageId,
  }) async {
    final peer = recipientIds.length == 1 ? recipientIds.first : null;
    final sealed = await _seal(body, peer);
    return _api.postJson(
      "/organizations/$organizationId/conversations",
      data: {
        "recipientIds": recipientIds,
        "body": sealed,
        if (subject != null) "subject": subject,
        "asGroup": asGroup,
        if (clientMessageId != null) "clientMessageId": clientMessageId,
      },
    );
  }

  /// Fiche d'un contact : même `telephone` que « Mon profil ».
  Future<Map<String, dynamic>> contact(
    String organizationId,
    String userId,
  ) {
    return _api.getJson(
      "/organizations/$organizationId/recipients",
      query: {"userId": userId},
    );
  }

  Future<Map<String, dynamic>> searchRecipients(
    String organizationId, {
    String query = "",
  }) {
    return _api.getJson(
      "/organizations/$organizationId/recipients",
      query: {"q": query},
    );
  }

  Future<Map<String, dynamic>> unreadCount(String organizationId) {
    return _api.getJson("/organizations/$organizationId/unread-count");
  }

  Future<Map<String, dynamic>> getSatisfactionPending(String organizationId) {
    return _api.getJson("/organizations/$organizationId/satisfaction/pending");
  }

  Future<Map<String, dynamic>> submitSatisfaction(
    String organizationId, {
    required String branchId,
    required int rating,
    String? comment,
  }) {
    return _api.postJson(
      "/organizations/$organizationId/satisfaction/submit",
      data: {
        "branchId": branchId,
        "rating": rating,
        if (comment != null && comment.trim().isNotEmpty)
          "comment": comment.trim(),
      },
    );
  }

  /// Statut en ligne réel (WS actif + lastSeen récent côté serveur).
  Future<Map<String, dynamic>> getPresence(
    String organizationId, {
    required List<String> userIds,
  }) {
    final ids = userIds.where((e) => e.isNotEmpty).toSet().take(50).join(",");
    return _api.getJson(
      "/organizations/$organizationId/presence",
      query: {"userIds": ids},
    );
  }

  /// Heartbeat : marque ce compte ONLINE (même sans WebSocket).
  Future<void> presenceHeartbeat(String organizationId) async {
    try {
      await _api.postJson("/organizations/$organizationId/presence");
    } catch (_) {
      // Ignore : présence best-effort.
    }
  }

  Future<void> conversationAction(
    String organizationId,
    String conversationId,
    String action, {
    String? userId,
    String? role,
  }) async {
    try {
      await _api.postJson(
        "/organizations/$organizationId/conversations/$conversationId/actions",
        data: {
          "action": action,
          if (userId != null) "userId": userId,
          if (role != null) "role": role,
        },
      );
    } catch (e) {
      // Certaines actions (read) restent best-effort hors ligne.
      if (action == "read") return;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getGroupSettings(
    String organizationId,
    String conversationId,
  ) {
    return _api.getJson(
      "/organizations/$organizationId/conversations/$conversationId/actions",
    );
  }

  Future<Map<String, dynamic>> startCall(
    String organizationId, {
    required String calleeId,
    String kind = "AUDIO",
    String? conversationId,
  }) {
    return _api.postJson(
      "/organizations/$organizationId/calls",
      data: {
        "calleeId": calleeId,
        "kind": kind,
        if (conversationId != null) "conversationId": conversationId,
      },
    );
  }

  Future<Map<String, dynamic>> callAction(
    String organizationId,
    String callId, {
    required String action,
  }) {
    return _api.postJson(
      "/organizations/$organizationId/calls/$callId/actions",
      data: {"action": action},
    );
  }
}
