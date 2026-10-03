import "dart:convert";

import "package:flutter/foundation.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:shared_preferences/shared_preferences.dart";

/// Persistance session : SharedPreferences (fiable web + mobile)
/// + SecureStorage en complément sur plateformes natives.
class TokenStore {
  TokenStore({FlutterSecureStorage? secure})
      : _secure = secure ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const tokenKey = "klambo_auth_token";
  static const meKey = "klambo_me_snapshot";

  final FlutterSecureStorage _secure;
  SharedPreferences? _prefs;

  Future<SharedPreferences> _prefsReady() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> saveToken(String token) async {
    final prefs = await _prefsReady();
    await prefs.setString(tokenKey, token);
    if (!kIsWeb) {
      try {
        await _secure.write(key: tokenKey, value: token);
      } catch (_) {}
    }
  }

  Future<String?> getToken() async {
    final prefs = await _prefsReady();
    final fromPrefs = prefs.getString(tokenKey);
    if (fromPrefs != null && fromPrefs.isNotEmpty) return fromPrefs;

    if (!kIsWeb) {
      try {
        final fromSecure = await _secure.read(key: tokenKey);
        if (fromSecure != null && fromSecure.isNotEmpty) {
          await prefs.setString(tokenKey, fromSecure);
          return fromSecure;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> clearToken() async {
    final prefs = await _prefsReady();
    await prefs.remove(tokenKey);
    await prefs.remove(meKey);
    if (!kIsWeb) {
      try {
        await _secure.delete(key: tokenKey);
      } catch (_) {}
    }
  }

  Future<void> saveMeSnapshot(Map<String, dynamic> me) async {
    final prefs = await _prefsReady();
    await prefs.setString(meKey, jsonEncode(me));
  }

  Future<Map<String, dynamic>?> getMeSnapshot() async {
    final prefs = await _prefsReady();
    final raw = prefs.getString(meKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }
}
