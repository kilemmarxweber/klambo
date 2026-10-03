import "package:shared_preferences/shared_preferences.dart";

/// Préférences alertes (sons + notifications).
class AlertPrefs {
  AlertPrefs._();
  static final AlertPrefs instance = AlertPrefs._();

  static const _soundsKey = "klambo_alert_sounds";
  static const _messageNotifKey = "klambo_alert_message_notif";
  static const _callNotifKey = "klambo_alert_call_notif";
  static const _permAskedKey = "klambo_notif_perm_asked";

  bool soundsEnabled = true;
  bool messageNotificationsEnabled = true;
  bool callNotificationsEnabled = true;
  bool permissionAsked = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    soundsEnabled = prefs.getBool(_soundsKey) ?? true;
    messageNotificationsEnabled = prefs.getBool(_messageNotifKey) ?? true;
    callNotificationsEnabled = prefs.getBool(_callNotifKey) ?? true;
    permissionAsked = prefs.getBool(_permAskedKey) ?? false;
  }

  Future<void> setSoundsEnabled(bool value) async {
    soundsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundsKey, value);
  }

  Future<void> setMessageNotificationsEnabled(bool value) async {
    messageNotificationsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_messageNotifKey, value);
  }

  Future<void> setCallNotificationsEnabled(bool value) async {
    callNotificationsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_callNotifKey, value);
  }

  Future<void> markPermissionAsked() async {
    permissionAsked = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_permAskedKey, true);
  }
}
