import "package:klambo_messagerie/data/api_client.dart";

class CallsRepository {
  CallsRepository(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> iceServers() {
    return _api.getJson("/calls/ice-servers");
  }

  Future<Map<String, dynamic>> startCall({
    required String organizationId,
    required String calleeId,
    required String kind,
    String? conversationId,
    Map<String, dynamic>? sdp,
    String? callerName,
  }) {
    return _api.postJson(
      "/organizations/$organizationId/calls",
      data: {
        "calleeId": calleeId,
        "kind": kind,
        if (conversationId != null) "conversationId": conversationId,
        if (sdp != null) "sdp": sdp,
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
  }) {
    return _api.postJson(
      "/organizations/$organizationId/calls/$callId/actions",
      data: {
        "action": action,
        if (endReason != null) "endReason": endReason,
        if (sdp != null) "sdp": sdp,
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
