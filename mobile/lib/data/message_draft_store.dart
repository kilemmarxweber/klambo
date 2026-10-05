import "package:shared_preferences/shared_preferences.dart";

/// Brouillons de saisie par conversation (persistance discrète locale).
class MessageDraftStore {
  MessageDraftStore._();

  static const _prefix = "klambo_draft_";
  static SharedPreferences? _prefs;

  static Future<SharedPreferences> _ready() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  static String _key(String organizationId, String conversationId) =>
      "$_prefix${organizationId}_$conversationId";

  static Future<String?> load({
    required String organizationId,
    required String conversationId,
  }) async {
    final prefs = await _ready();
    final text = prefs.getString(_key(organizationId, conversationId));
    if (text == null || text.trim().isEmpty) return null;
    return text;
  }

  static Future<void> save({
    required String organizationId,
    required String conversationId,
    required String text,
  }) async {
    final prefs = await _ready();
    final key = _key(organizationId, conversationId);
    final trimmed = text.trimRight();
    if (trimmed.trim().isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, trimmed);
  }

  static Future<void> clear({
    required String organizationId,
    required String conversationId,
  }) async {
    final prefs = await _ready();
    await prefs.remove(_key(organizationId, conversationId));
  }
}
