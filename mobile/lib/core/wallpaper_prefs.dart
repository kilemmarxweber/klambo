import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

/// Les trois fonds générés pour les discussions.
enum WallpaperStyle {
  messages,
  android,
  mix,
}

class WallpaperPrefs extends ChangeNotifier {
  WallpaperPrefs._();
  static final WallpaperPrefs instance = WallpaperPrefs._();

  static const _key = "klambo_wallpaper_style";

  WallpaperStyle style = WallpaperStyle.messages;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    style = _fromStorage(prefs.getString(_key));
    notifyListeners();
  }

  Future<void> setStyle(WallpaperStyle value) async {
    if (style == value) return;
    style = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value.name);
  }

  static WallpaperStyle _fromStorage(String? raw) {
    for (final style in WallpaperStyle.values) {
      if (style.name == raw) return style;
    }
    return WallpaperStyle.messages;
  }
}
