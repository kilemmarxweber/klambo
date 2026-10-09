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

  /// Vrai après le démarrage du service Android qui écoute les appels
  /// écran verrouillé ou application quittée.
  static bool serviceStarted = false;

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
      serviceStarted = true;
      unawaited(_askCallPrivilegesOnce());
    } catch (e) {
      serviceStarted = false;
      debugPrint("[bg] start: $e");
    }
  }

  static Future<void> stop() async {
    serviceStarted = false;
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

  /// Notification d'appel en cours pour que l'OS ne tue pas le micro.
  static Future<void> setCallOngoing({
    required String name,
    required bool video,
  }) async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<void>("callOngoing", {
        "name": name,
        "video": video,
      });
    } catch (e) {
      debugPrint("[bg] callOngoing: $e");
    }
  }

  static Future<void> setCallIdle() async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<void>("callIdle");
    } catch (e) {
      debugPrint("[bg] callIdle: $e");
    }
  }

  /// Offre reçue par la notif Android. `autoAccept` = bouton Décrocher.
  static Future<Map<String, dynamic>?> takePendingCall() async {
    if (!_android) return null;
    try {
      final raw = await _channel.invokeMethod<dynamic>("takePendingCall");
      if (raw is Map) return Map<String, dynamic>.from(raw);
    } catch (e) {
      debugPrint("[bg] pending call: $e");
    }
    return null;
  }

  /// Jeton push si une intégration FCM est branchée. Sinon null.
  static Future<String?> pushToken() async {
    if (!_android) return null;
    try {
      return await _channel.invokeMethod<String>("pushToken");
    } catch (_) {
      return null;
    }
  }

  /// Coupe la sonnerie native une fois que l'écran d'appel Flutter est prêt.
  static Future<void> stopNativeRing() async {
    if (!_android || !serviceStarted) return;
    try {
      await _channel.invokeMethod<void>("stopRing");
    } catch (e) {
      debugPrint("[bg] stopRing: $e");
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

  /// Une seule demande : batterie (sinon Doze coupe messages/appels verrouillés).
  static Future<void> _askCallPrivilegesOnce() async {
    if (!_android) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_batteryAskedKey) == true) return;
      await prefs.setBool(_batteryAskedKey, true);
      await _channel.invokeMethod<bool>("prepareIncomingCalls");
    } catch (e) {
      debugPrint("[bg] privileges: $e");
    }
  }

  /// Relance le service FGS (après retour premier plan / long verrouillage).
  static Future<void> ensureAlive() async {
    if (!_android) return;
    await touch();
    try {
      await _channel.invokeMethod<void>("start");
      serviceStarted = true;
    } catch (e) {
      debugPrint("[bg] ensureAlive: $e");
    }
  }

  /// Demande batterie non-optimisée (Doze coupe sinon l'écoute verrouillée).
  static Future<void> requestBatteryExemption() async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<bool>("prepareIncomingCalls");
    } catch (e) {
      debugPrint("[bg] battery: $e");
    }
  }
}
