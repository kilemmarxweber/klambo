import "package:klambo_messagerie/core/config.dart";

/// Résout une URL d'image Eteyelo (relative ou absolue).
String? resolveImageUrl(Object? src) {
  if (src == null) return null;
  if (src is! String) return null;
  final trimmed = src.trim();
  if (trimmed.isEmpty) return null;

  if (trimmed.startsWith("http://") ||
      trimmed.startsWith("https://") ||
      trimmed.startsWith("data:")) {
    return trimmed;
  }

  final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r"/+$"), "");
  if (trimmed.startsWith("/")) return "$base$trimmed";
  return "$base/uploads/$trimmed";
}

String initialsFromName(String name) {
  final parts = name.trim().split(RegExp(r"\s+")).where((p) => p.isNotEmpty);
  final list = parts.toList();
  if (list.isEmpty) return "?";
  if (list.length == 1) {
    final s = list.first;
    return s.length >= 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase();
  }
  return "${list[0][0]}${list[1][0]}".toUpperCase();
}
