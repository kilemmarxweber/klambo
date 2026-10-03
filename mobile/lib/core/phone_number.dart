/// Lit un numéro dans un objet API (champs et objets imbriqués).
/// Si le numéro est collé au prénom ou au nom, il est quand même repris.
String? extractPhoneNumber(dynamic source, {int depth = 0}) {
  if (source == null || depth > 2) return null;
  if (source is num) {
    return _asPhone(source.toString());
  }
  if (source is String) {
    return findPhoneInText(source);
  }
  if (source is! Map) return null;

  final fromField = _phoneField(source, depth: depth);
  if (fromField != null) return fromField;
  if (depth == 0) {
    for (final nestedKey in ["user", "profile", "person", "contact", "sender"]) {
      final nested = _ignoreCase(source, nestedKey);
      if (nested is Map) {
        final found = extractPhoneNumber(nested, depth: depth + 1);
        if (found != null) return found;
      }
    }
  }
  for (final key in _identityKeys) {
    final value = _ignoreCase(source, key);
    if (value is! String) continue;
    final found = findPhoneInText(value);
    if (found != null) return found;
  }
  return null;
}

/// Téléphone du compte (obligatoire à la connexion), pas un numéro collé au nom.
String? accountTelephone(dynamic source) {
  final phone = _phoneField(source is Map ? source : {"telephone": source});
  if (phone != null) return formatAccountPhone(phone);
  if (source is! Map) return null;
  for (final nestedKey in ["user", "profile", "person", "contact", "sender"]) {
    final nested = _ignoreCase(source, nestedKey);
    if (nested is Map) {
      final found = accountTelephone(nested);
      if (found != null) return found;
    }
  }
  return null;
}

/// Réponse annuaire : `{ item }` ou `{ items: [...] }`, téléphone sur l'objet ou sur `user`.
String? phoneFromApiPayload(dynamic data, {String? userId}) {
  if (data is! Map) return accountTelephone(data) ?? extractPhoneNumber(data);
  final map = Map<String, dynamic>.from(data);

  String? fromRecord(Map raw) {
    if (userId != null && userId.isNotEmpty && !_recordIsUser(raw, userId)) {
      return null;
    }
    return accountTelephone(raw) ?? extractPhoneNumber(raw);
  }

  for (final key in ["item", "recipient", "user", "profile"]) {
    final nested = map[key];
    if (nested is Map) {
      final found = fromRecord(Map<String, dynamic>.from(nested));
      if (found != null) return found;
    }
  }

  final items = map["items"] ?? map["recipients"] ?? map["users"];
  if (items is List) {
    String? only;
    var count = 0;
    for (final raw in items) {
      if (raw is! Map) continue;
      count++;
      final record = Map<String, dynamic>.from(raw);
      final found = fromRecord(record);
      if (found != null) return found;
      only ??= accountTelephone(record) ?? extractPhoneNumber(record);
    }
    if (count == 1) return only;
  }

  return fromRecord(map);
}

bool _recordIsUser(Map raw, String userId) {
  final ids = <String>[
    raw["userId"]?.toString() ?? "",
    raw["id"]?.toString() ?? "",
  ];
  final user = raw["user"];
  if (user is Map) ids.add(user["id"]?.toString() ?? "");
  final known = ids.where((id) => id.isNotEmpty).toList();
  if (known.isEmpty) return true;
  return known.contains(userId);
}

/// Affiche `+243844952966`.
String formatAccountPhone(String phone) {
  var kept = phone.replaceAll(RegExp(r"[^\d+]"), "");
  if (kept.startsWith("00")) kept = "+${kept.substring(2)}";
  if (!kept.startsWith("+") && kept.startsWith("243")) kept = "+$kept";
  return kept;
}

String? _phoneField(Map source, {int depth = 0}) {
  if (depth > 2) return null;
  for (final entry in source.entries) {
    final key = entry.key.toString().toLowerCase().replaceAll("_", "");
    if (!_phoneKeyNames.contains(key)) continue;
    final value = entry.value;
    if (value is Map) {
      final found = _phoneField(value, depth: depth + 1);
      if (found != null) return found;
      continue;
    }
    final found = findPhoneInText(value?.toString());
    if (found != null) return found;
  }
  return null;
}

dynamic _ignoreCase(Map source, String key) {
  if (source.containsKey(key)) return source[key];
  final wanted = key.toLowerCase();
  for (final entry in source.entries) {
    if (entry.key.toString().toLowerCase() == wanted) return entry.value;
  }
  return null;
}

const _phoneKeyNames = {
  "telephone",
  "phone",
  "phonenumber",
  "tel",
  "mobile",
  "mobilephone",
  "gsm",
  "numero",
  "numéro",
  "contact",
  "whatsapp",
  "msisdn",
  "e164",
  "phonee164",
  "telephonenumber",
  "phonenumbers",
};

const _identityKeys = [
  "prenom",
  "nom",
  "name",
  "title",
  "displayName",
  "fullName",
  "lastName",
  "postnom",
  "senderName",
  "senderPrenom",
  "senderNom",
  "senderPostnom",
];

/// Numéro présent dans un texte, même collé à un nom.
String? findPhoneInText(String? raw) {
  if (raw == null) return null;
  final text = raw.trim();
  if (text.isEmpty) return null;
  if (!_hasLetter(text)) return _asPhone(text);
  for (final match in _embeddedPhone.allMatches(text)) {
    final chunk = match.group(0)!.trim();
    final phone = _asPhone(chunk);
    if (phone != null) return phone;
  }
  return null;
}

/// Retire le numéro pour ne pas l'afficher comme prénom ou nom.
String textWithoutPhone(String? raw) {
  if (raw == null) return "";
  final text = raw.trim();
  if (text.isEmpty) return "";
  final phone = findPhoneInText(text);
  if (phone == null) return text;
  return text.replaceFirst(phone, " ").replaceAll(RegExp(r"\s+"), " ").trim();
}

final _embeddedPhone = RegExp(
  r"(?<![\w@./])(?:\+\d{1,3}[\s.\-]?)?(?:\(?\d{1,4}\)?[\s.\-]?)?\d(?:[\d\s.\-]{5,}\d)",
);

bool _hasLetter(String text) => RegExp(r"[A-Za-zÀ-ÿ]").hasMatch(text);

String? _asPhone(String raw) {
  final text = raw.trim();
  if (text.isEmpty || _hasLetter(text)) return null;
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
