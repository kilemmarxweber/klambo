import "dart:convert";

import "package:shared_preferences/shared_preferences.dart";

/// Cache local des conversations / messages déjà chargés (lecture hors ligne).
class MessageCache {
  MessageCache();

  static const _prefixConv = "klambo_cache_conv_";
  static const _prefixMsg = "klambo_cache_msg_";

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ready() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> saveConversations(
    String organizationId,
    List<Map<String, dynamic>> items,
  ) async {
    final prefs = await _ready();
    await prefs.setString(
      "$_prefixConv$organizationId",
      jsonEncode(items),
    );
  }

  Future<List<Map<String, dynamic>>?> getConversations(
    String organizationId,
  ) async {
    final prefs = await _ready();
    final raw = prefs.getString("$_prefixConv$organizationId");
    return _decodeList(raw);
  }

  Future<void> saveMessages(
    String organizationId,
    String conversationId,
    List<dynamic> items,
  ) async {
    final prefs = await _ready();
    await prefs.setString(
      "$_prefixMsg${organizationId}_$conversationId",
      jsonEncode(items),
    );
  }

  Future<List<dynamic>?> getMessages(
    String organizationId,
    String conversationId,
  ) async {
    final prefs = await _ready();
    final raw =
        prefs.getString("$_prefixMsg${organizationId}_$conversationId");
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded;
    } catch (_) {}
    return null;
  }

  List<Map<String, dynamic>>? _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return null;
    }
  }
}
