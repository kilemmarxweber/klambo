import "dart:typed_data";

import "package:dio/dio.dart";
import "package:http_parser/http_parser.dart";
import "package:klambo_messagerie/data/api_client.dart";
import "package:klambo_messagerie/data/message_cache.dart";

class MessagingRepository {
  MessagingRepository(this._api, {MessageCache? cache})
      : _cache = cache ?? MessageCache();

  final ApiClient _api;
  final MessageCache _cache;

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
      // Un delta ne remplace pas le cache de toute la liste.
      if (!delta) await _cache.saveConversations(organizationId, mapped);
      return {...data, "fromCache": false};
    } catch (e) {
      final cached = await _cache.getConversations(organizationId);
      if (cached != null) {
        return {"items": cached, "fromCache": true};
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
      await _cache.saveMessages(organizationId, conversationId, items);
      return {...data, "fromCache": false};
    } catch (e) {
      final cached = await _cache.getMessages(organizationId, conversationId);
      if (cached != null) {
        return {"items": cached, "fromCache": true};
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
  }) {
    return _api.postJson(
      "/organizations/$organizationId/conversations/$conversationId/messages",
      data: {
        "body": body,
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
  }) {
    return _api.patchJson(
      "/organizations/$organizationId/conversations/$conversationId/messages/$messageId",
      data: {"body": body},
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
  }) async {
    try {
      final form = FormData.fromMap({
        if (body.trim().isNotEmpty) "body": body.trim(),
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
  }) {
    return _api.postJson(
      "/organizations/$organizationId/conversations",
      data: {
        "recipientIds": recipientIds,
        "body": body,
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
    List<String>? messageIds,
  }) async {
    try {
      await _api.postJson(
        "/organizations/$organizationId/conversations/$conversationId/actions",
        data: {
          "action": action,
          if (userId != null) "userId": userId,
          if (role != null) "role": role,
          if (messageIds != null && messageIds.isNotEmpty)
            "messageIds": messageIds,
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
