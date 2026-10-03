import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:shared_preferences/shared_preferences.dart";

/// Maintient Klambocore en arrière-plan (Android) pour les alertes
/// écran verrouillé ou application quittée.
class BackgroundAlerts {
  BackgroundAlerts._();

  static const _channel = MethodChannel("klambo/background");
  static const _heartbeatKey = "klambo_ui_heartbeat";
  static const _batteryAskedKey = "klambo_battery_asked";
  static Timer? _beat;

  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> start() async {
    if (!_android) return;
    await touch();
    _beat ??= Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(touch());
    });
    try {
      await _channel.invokeMethod<void>("start");
    } catch (e) {
      debugPrint("[bg] start: $e");
    }
  }

  static Future<void> stop() async {
    _beat?.cancel();
    _beat = null;
    if (!_android) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_heartbeatKey, 0);
    } catch (_) {}
    try {
      await _channel.invokeMethod<void>("stop");
    } catch (e) {
      debugPrint("[bg] stop: $e");
    }
  }

  /// Tant que cette horloge est fraîche, Flutter affiche lui-même l'alerte.
  static Future<void> touch() async {
    if (!_android) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _heartbeatKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  /// Une seule demande : sans ça, Android endort le téléphone et coupe le son.
  static Future<void> askBatteryExemptionOnce() async {
    if (!_android) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_batteryAskedKey) == true) return;
      await prefs.setBool(_batteryAskedKey, true);
      await _channel.invokeMethod<bool>("battery");
    } catch (e) {
      debugPrint("[bg] battery: $e");
    }
  }
}
