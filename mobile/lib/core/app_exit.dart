import "package:flutter/foundation.dart";
import "package:flutter/services.dart";

/// Ferme l’app (Android / desktop). No-op sur le web.
Future<void> exitApp() async {
  if (kIsWeb) return;
  await SystemNavigator.pop();
}
