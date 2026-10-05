import "package:klambo_messagerie/data/api_client.dart";

class ParentRepository {
  ParentRepository(this._api);

  final ApiClient _api;

  Future<List<Map<String, dynamic>>> listChildren(String organizationId) async {
    final data = await _api.getJson(
      "/organizations/$organizationId/parent/children",
    );
    final items = (data["items"] as List?) ?? const [];
    return items
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> feesStatus({
    required String organizationId,
    required String studentId,
  }) {
    return _api.getJson(
      "/organizations/$organizationId/parent/fees/status",
      query: {"studentId": studentId},
    );
  }

  /// Stub Mobile Money : instructions localisées (pas encore de deep link).
  Future<Map<String, dynamic>> feesPayLink({
    required String organizationId,
    required String studentId,
    required String fraisId,
    String lang = "fr",
  }) {
    return _api.getJson(
      "/organizations/$organizationId/parent/fees/pay-link",
      query: {
        "studentId": studentId,
        "fraisId": fraisId,
        "lang": lang,
      },
    );
  }

  Future<Map<String, dynamic>> gradesStatus({
    required String organizationId,
    required String studentId,
  }) {
    return _api.getJson(
      "/organizations/$organizationId/parent/grades/status",
      query: {"studentId": studentId},
    );
  }

  Future<Map<String, dynamic>> bulletinMeta({
    required String organizationId,
    required String studentId,
    int? periodId,
  }) {
    return _api.getJson(
      "/organizations/$organizationId/parent/bulletin/pdf",
      query: {
        "studentId": studentId,
        if (periodId != null) "periodId": periodId.toString(),
      },
    );
  }

  /// Accusé de lecture certifié pour un avis officiel (`__NOTIFY__`).
  Future<Map<String, dynamic>> acknowledgeNotice({
    required String organizationId,
    required String messageId,
  }) {
    return _api.postJson(
      "/organizations/$organizationId/notices/$messageId/ack",
    );
  }

  Future<Map<String, dynamic>> noticeAckStatus({
    required String organizationId,
    required String messageId,
  }) {
    return _api.getJson(
      "/organizations/$organizationId/notices/$messageId/ack",
    );
  }
}
