/// Lit un numéro dans un objet API (champs et objets imbriqués).
String? extractPhoneNumber(dynamic source, {int depth = 0}) {
  if (source == null || depth > 2) return null;
  if (source is num) {
    return _asPhone(source.toString());
  }
  if (source is String) {
    return _asPhone(source);
  }
  if (source is! Map) return null;

  const keys = [
    "telephone",
    "phone",
    "phoneNumber",
    "phone_number",
    "tel",
    "mobile",
    "mobilePhone",
    "gsm",
    "numero",
    "numéro",
    "contact",
    "whatsapp",
    "msisdn",
    "e164",
    "phoneE164",
  ];
  for (final key in keys) {
    if (!source.containsKey(key)) continue;
    final found = extractPhoneNumber(source[key], depth: depth + 1);
    if (found != null) return found;
  }
  if (depth > 0) return null;
  for (final nestedKey in ["user", "profile", "person", "contact", "sender"]) {
    final nested = source[nestedKey];
    if (nested is Map) {
      final found = extractPhoneNumber(nested, depth: depth + 1);
      if (found != null) return found;
    }
  }
  return null;
}

String? _asPhone(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final digits = text.replaceAll(RegExp(r"\D"), "");
  if (digits.length < 8 || digits.length > 15) return null;
  return text;
}

/// Numéro utilisable dans un lien `tel:`.
String dialablePhone(String phone) {
  final kept = phone.replaceAll(RegExp(r"[^\d+]"), "");
  if (kept.startsWith("00")) return "+${kept.substring(2)}";
  return kept;
}
