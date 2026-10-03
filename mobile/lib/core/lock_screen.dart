import "package:flutter/foundation.dart";
import "package:flutter/services.dart";

const _lockScreenChannel =
    MethodChannel("com.klambocore.klambo/lock_screen");

/// Active/désactive l’affichage par-dessus l’écran verrouillé (appels seulement).
Future<void> setLockScreenVisible(bool visible) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _lockScreenChannel.invokeMethod("setLockScreenVisible", {
      "visible": visible,
    });
  } catch (e) {
    debugPrint("[lock_screen] $e");
  }
}
