import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

class AppConfig {
  AppConfig._();

  /// Domaine Eteyelo de production (défaut des builds release).
  static const productionBaseUrl = "https://klambocore.com";

  /// Override compile-time : `--dart-define=API_BASE_URL=https://...`
  static const _apiBaseUrlOverride = String.fromEnvironment("API_BASE_URL");

  static const _prefsKey = "klambo_api_base_url";

  /// Saisie utilisateur (écran téléphone) — prioritaire si non vide.
  static String? _runtimeOverride;

  static const mobileApiPrefix = "/api/mobile/v1";

  /// Charge l’URL persistée avant le 1er appel réseau.
  static Future<void> loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey)?.trim();
    if (saved != null && saved.isNotEmpty) {
      _runtimeOverride = normalizeBaseUrl(saved);
    }
  }

  static Future<void> persistBaseUrl(String url) async {
    final normalized = normalizeBaseUrl(url);
    _runtimeOverride = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, normalized);
  }

  static Future<void> clearPersistedBaseUrl() async {
    _runtimeOverride = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  static String normalizeBaseUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return defaultApiBaseUrl;
    if (!url.contains("://")) {
      url = "https://$url";
    }
    while (url.endsWith("/")) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Défaut sans préférence utilisateur.
  static String get defaultApiBaseUrl {
    if (_apiBaseUrlOverride.isNotEmpty) return _apiBaseUrlOverride;
    if (kReleaseMode) return productionBaseUrl;
    if (kIsWeb) return "http://localhost:3000";
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return "http://10.0.2.2:3000";
      default:
        return "http://localhost:3000";
    }
  }

  /// Base URL Eteyelo active (sans slash final).
  static String get apiBaseUrl => _runtimeOverride ?? defaultApiBaseUrl;

  static String get mobileBase => "$apiBaseUrl$mobileApiPrefix";

  static bool get hasCustomBaseUrl =>
      _runtimeOverride != null && _runtimeOverride!.isNotEmpty;
}
