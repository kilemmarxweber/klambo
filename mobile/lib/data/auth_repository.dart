import "dart:typed_data";

import "package:dio/dio.dart";
import "package:http_parser/http_parser.dart";
import "package:klambo_messagerie/data/api_client.dart";

class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> requestOtp(String phone) {
    return _api.postJson("/auth/otp/request", data: {"phone": phone});
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String code,
  }) async {
    final data = await _api.postJson(
      "/auth/otp/verify",
      data: {"phone": phone, "code": code},
    );
    final token = data["token"]?.toString();
    if (token != null && token.isNotEmpty) {
      await _api.saveToken(token);
    }
    return data;
  }

  MediaType _imageMediaType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith(".png")) return MediaType("image", "png");
    if (lower.endsWith(".webp")) return MediaType("image", "webp");
    if (lower.endsWith(".gif")) return MediaType("image", "gif");
    return MediaType("image", "jpeg");
  }

  Future<Map<String, dynamic>> completeProfile({
    required String name,
    String? prenom,
    String? postnom,
    Uint8List? imageBytes,
    String imageFilename = "avatar.jpg",
  }) async {
    try {
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final form = FormData.fromMap({
          "name": name,
          if (prenom != null) "prenom": prenom,
          if (postnom != null) "postnom": postnom,
          "image": MultipartFile.fromBytes(
            imageBytes,
            filename: imageFilename,
            contentType: _imageMediaType(imageFilename),
          ),
        });
        final res = await _api.dio.post("/auth/profile", data: form);
        final raw = res.data;
        if (raw is! Map) throw Exception("Réponse profil invalide");
        if (raw["ok"] == false) {
          throw Exception(raw["error"]?.toString() ?? "Profil échoué");
        }
        return Map<String, dynamic>.from(raw["data"] as Map);
      }
      return await _api.postJson(
        "/auth/profile",
        data: {
          "name": name,
          if (prenom != null) "prenom": prenom,
          if (postnom != null) "postnom": postnom,
        },
      );
    } on DioException catch (e) {
      final msg = e.response?.data is Map
          ? e.response!.data["error"]?.toString()
          : null;
      throw Exception(msg ?? e.message ?? "Upload photo échoué");
    }
  }

  Future<Map<String, dynamic>> me() => _api.getJson("/me");

  Future<Map<String, dynamic>> setActiveOrganization(String organizationId) {
    return _api.patchJson(
      "/me",
      data: {"activeOrganizationId": organizationId},
    );
  }

  Future<void> signOut() async {
    try {
      await _api.postJson("/auth/sign-out");
    } finally {
      await _api.clearToken();
    }
  }
}
