import "dart:async";

import "package:connectivity_plus/connectivity_plus.dart";
import "package:flutter/foundation.dart";
import "package:shared_preferences/shared_preferences.dart";

/// Mode économie de données (P0) : médias à la demande, appels vidéo légers.
class DataSaverPrefs extends ChangeNotifier {
  DataSaverPrefs._();
  static final DataSaverPrefs instance = DataSaverPrefs._();

  static const _manualKey = "klambo_data_saver";
  static const _autoKey = "klambo_data_saver_auto";

  bool enabled = false;
  bool autoOnMobile = true;
  bool _networkSuggestsSaver = false;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool get effectiveEnabled =>
      enabled || (autoOnMobile && _networkSuggestsSaver);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled = prefs.getBool(_manualKey) ?? false;
    autoOnMobile = prefs.getBool(_autoKey) ?? true;
    await _refreshConnectivity();
    _sub?.cancel();
    _sub = Connectivity().onConnectivityChanged.listen((_) {
      unawaited(_refreshConnectivity());
    });
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (enabled == value) return;
    enabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_manualKey, value);
  }

  Future<void> setAutoOnMobile(bool value) async {
    if (autoOnMobile == value) return;
    autoOnMobile = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoKey, value);
  }

  Future<void> _refreshConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final mobileOnly = results.isNotEmpty &&
          results.every(
            (r) =>
                r == ConnectivityResult.mobile ||
                r == ConnectivityResult.none,
          );
      if (_networkSuggestsSaver == mobileOnly) return;
      _networkSuggestsSaver = mobileOnly;
      notifyListeners();
    } catch (e) {
      debugPrint("[data-saver] connectivity: $e");
    }
  }

  void disposeListener() {
    _sub?.cancel();
    _sub = null;
  }
}
