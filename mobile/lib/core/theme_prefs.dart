import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

/// Préférence thème : clair / sombre / système (activable au choix).
class ThemePrefs extends ChangeNotifier {
  ThemePrefs._();
  static final ThemePrefs instance = ThemePrefs._();

  static const _key = "klambo_theme_mode";

  ThemeMode mode = ThemeMode.light;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    mode = _fromStorage(prefs.getString(_key));
    notifyListeners();
  }

  Future<void> setMode(ThemeMode value) async {
    if (mode == value) return;
    mode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _toStorage(value));
  }

  static ThemeMode _fromStorage(String? raw) {
    switch (raw) {
      case "dark":
        return ThemeMode.dark;
      case "system":
        return ThemeMode.system;
      case "light":
        return ThemeMode.light;
      default:
        return ThemeMode.light;
    }
  }

  static String _toStorage(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return "dark";
      case ThemeMode.system:
        return "system";
      case ThemeMode.light:
        return "light";
    }
  }
}
