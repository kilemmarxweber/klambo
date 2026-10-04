import "package:klambo_messagerie/data/api_client.dart";

class CallsRepository {
  CallsRepository(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> iceServers() {
    return _api.getJson("/calls/ice-servers");
  }

  Future<void> putCallIdentity(String publicKey) async {
    await _api.postJson(
      "/calls/identity",
      data: {"publicKey": publicKey},
    );
  }

  Future<Map<String, dynamic>> peerCallIdentity(String userId) {
    return _api.getJson("/calls/identity/$userId");
  }

  Future<void> registerPushToken({
    required String token,
    required String platform,
  }) async {
    await _api.postJson(
      "/calls/push-token",
      data: {"token": token, "platform": platform},
    );
  }

  Future<Map<String, dynamic>> startCall({
    required String organizationId,
    required String calleeId,
    required String kind,
    String? conversationId,
    Map<String, dynamic>? sdp,
    Map<String, dynamic>? dtls,
    String? callerName,
  }) {
    return _api.postJson(
      "/organizations/$organizationId/calls",
      data: {
        "calleeId": calleeId,
        "kind": kind,
        if (conversationId != null) "conversationId": conversationId,
        if (sdp != null) "sdp": sdp,
        if (dtls != null) "dtls": dtls,
        if (callerName != null) "callerName": callerName,
      },
    );
  }

  Future<Map<String, dynamic>> callAction({
    required String organizationId,
    required String callId,
    required String action,
    String? endReason,
    Map<String, dynamic>? sdp,
    Map<String, dynamic>? dtls,
  }) {
    return _api.postJson(
      "/organizations/$organizationId/calls/$callId/actions",
      data: {
        "action": action,
        if (endReason != null) "endReason": endReason,
        if (sdp != null) "sdp": sdp,
        if (dtls != null) "dtls": dtls,
      },
    );
  }

  /// Sonneries en cours pour l'utilisateur (secours si le websocket rate).
  Future<Map<String, dynamic>> incoming() {
    return _api.getJson("/calls/incoming");
  }

  Future<Map<String, dynamic>> callSignal({
    required String organizationId,
    required String callId,
  }) {
    return _api.getJson(
      "/organizations/$organizationId/calls/$callId/signal",
    );
  }

  Future<void> postSignal({
    required String organizationId,
    required String callId,
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    await _api.postJson(
      "/organizations/$organizationId/calls/$callId/signal",
      data: {"type": type, "payload": payload},
    );
  }

  Future<Map<String, dynamic>> history(String organizationId) {
    return _api.getJson("/organizations/$organizationId/calls");
  }
}
