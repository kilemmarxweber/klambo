import "package:flutter_riverpod/flutter_riverpod.dart";

/// Conversation actuellement ouverte (pas de bannière si le fil est déjà à l'écran).
final activeConversationIdProvider = StateProvider<String?>((ref) => null);
