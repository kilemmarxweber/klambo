import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

/// Suit les conversations où un correspondant est en train d'écrire.
class TypingStore extends ChangeNotifier {
  final Map<String, Timer> _timers = {};
  final Set<String> _active = {};

  bool isTyping(String? conversationId) =>
      conversationId != null &&
      conversationId.isNotEmpty &&
      _active.contains(conversationId);

  void note(
    String conversationId, {
    Duration ttl = const Duration(seconds: 4),
  }) {
    if (conversationId.isEmpty) return;
    final wasActive = _active.contains(conversationId);
    _active.add(conversationId);
    _timers[conversationId]?.cancel();
    _timers[conversationId] = Timer(ttl, () {
      _active.remove(conversationId);
      _timers.remove(conversationId);
      notifyListeners();
    });
    if (!wasActive) notifyListeners();
  }

  void clear(String conversationId) {
    _timers[conversationId]?.cancel();
    _timers.remove(conversationId);
    if (_active.remove(conversationId)) notifyListeners();
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _active.clear();
    super.dispose();
  }
}

final typingStoreProvider = ChangeNotifierProvider<TypingStore>((ref) {
  final store = TypingStore();
  ref.onDispose(store.dispose);
  return store;
});
