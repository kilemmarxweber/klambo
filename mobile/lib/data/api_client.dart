import "package:dio/dio.dart";
import "package:klambo_messagerie/core/config.dart";
import "package:klambo_messagerie/core/l10n.dart";
import "package:klambo_messagerie/data/token_store.dart";

class ApiClient {
  ApiClient({TokenStore? tokenStore}) : _tokens = tokenStore ?? TokenStore() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.mobileBase,
        connectTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(seconds: 45),
        headers: {"Accept": "application/json"},
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          options.baseUrl = AppConfig.mobileBase;
          final token = await _tokens.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers["Authorization"] = "Bearer $token";
          }
          handler.next(options);
        },
      ),
    );
  }

  late final Dio _dio;
  final TokenStore _tokens;

  Dio get dio => _dio;
  TokenStore get tokens => _tokens;

  Future<void> setApiBaseUrl(String url) async {
    await AppConfig.persistBaseUrl(url);
    _dio.options.baseUrl = AppConfig.mobileBase;
  }

  Future<void> saveToken(String token) => _tokens.saveToken(token);

  Future<String?> getToken() => _tokens.getToken();

  Future<void> clearToken() => _tokens.clearToken();

  Future<void> saveMeSnapshot(Map<String, dynamic> me) =>
      _tokens.saveMeSnapshot(me);

  Future<Map<String, dynamic>?> getMeSnapshot() => _tokens.getMeSnapshot();

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    try {
      final res = await _dio.post(path, data: data);
      return _unwrap(res.data);
    } on DioException catch (e) {
      throw ApiException(_friendlyDioError(e), statusCode: e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio.get(path, queryParameters: query);
      return _unwrap(res.data);
    } on DioException catch (e) {
      throw ApiException(_friendlyDioError(e), statusCode: e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    dynamic data,
  }) async {
    try {
      final res = await _dio.patch(path, data: data);
      return _unwrap(res.data);
    } on DioException catch (e) {
      throw ApiException(_friendlyDioError(e), statusCode: e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> deleteJson(String path) async {
    try {
      final res = await _dio.delete(path);
      return _unwrap(res.data);
    } on DioException catch (e) {
      throw ApiException(_friendlyDioError(e), statusCode: e.response?.statusCode);
    }
  }

  L10n get _l10n => LocaleController.instance.l10n;

  String _friendlyDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return _l10n.connectionWeak;
      case DioExceptionType.connectionError:
        return _l10n.connectionFailed;
      default:
    }
    final msg = e.response?.data is Map
        ? (e.response!.data["error"]?.toString())
        : null;
    return msg ?? e.message ?? _l10n.networkError;
  }

  Map<String, dynamic> _unwrap(dynamic raw) {
    if (raw is! Map) {
      throw Exception(_l10n.invalidResponse);
    }
    final map = Map<String, dynamic>.from(raw);
    if (map["ok"] == false) {
      throw Exception(map["error"]?.toString() ?? _l10n.apiError);
    }
    final data = map["data"];
    if (data is Map) return Map<String, dynamic>.from(data);
    return map;
  }
}

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  bool get isUnauthorized => statusCode == 401 || statusCode == 403;
  @override
  String toString() => message;
}
