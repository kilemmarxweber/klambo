import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:klambo_messagerie/features/auth/session_provider.dart";
import "package:klambo_messagerie/features/calls/call_hub.dart";

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
  StreamSubscription<Map<String, dynamic>>? sub;

  void bind(CallHub? hub) {
    sub?.cancel();
    sub = null;
    if (hub == null) return;
    sub = hub.messageEvents.listen((event) {
      final type = event["type"]?.toString() ?? "";
      if (type == "typing") {
        final convId = event["conversationId"]?.toString();
        final uid = event["userId"]?.toString();
        final me = ref.read(sessionProvider).me?["user"];
        final myId = me is Map ? me["id"]?.toString() : null;
        if (convId == null ||
            convId.isEmpty ||
            uid == null ||
            uid == myId) {
          return;
        }
        store.note(convId);
        return;
      }
      if (type == "message.created") {
        final payload = event["payload"];
        final convId = event["conversationId"]?.toString() ??
            (payload is Map ? payload["conversationId"]?.toString() : null);
        final senderId = event["senderId"]?.toString() ??
            (payload is Map ? payload["senderId"]?.toString() : null);
        final me = ref.read(sessionProvider).me?["user"];
        final myId = me is Map ? me["id"]?.toString() : null;
        // Seulement si l'autre a envoyé (pas notre propre echo).
        if (convId != null &&
            convId.isNotEmpty &&
            senderId != null &&
            senderId != myId) {
          store.clear(convId);
        }
      }
    });
  }

  ref.listen<CallHub?>(
    callHubProvider,
    (_, next) => bind(next),
    fireImmediately: true,
  );
  ref.onDispose(() {
    sub?.cancel();
    store.dispose();
  });
  return store;
});
