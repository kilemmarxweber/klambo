import "package:klambo_messagerie/core/phone_number.dart";

/// Prénom affiché : le numéro collé au texte n'est pas un prénom.
String personPrenom(String? prenom) => textWithoutPhone(prenom);

String _withoutLeading(String value, String token) {
  final piece = token.trim();
  var rest = value.trim();
  if (piece.isEmpty || rest.isEmpty) return rest;
  final prefix = "${piece.toLowerCase()} ";
  while (rest.toLowerCase().startsWith(prefix)) {
    rest = rest.substring(piece.length).trim();
  }
  if (rest.toLowerCase() == piece.toLowerCase()) return "";
  return rest;
}

/// Un seul nom de famille. [nom] s'il est rempli, sinon [name].
/// Un numéro collé au texte est retiré avant de couper le postnom.
String personNom({
  String? nom,
  String? name,
  String? prenom,
  String? postnom,
}) {
  final family = textWithoutPhone(
    (nom?.trim().isNotEmpty ?? false) ? nom!.trim() : (name?.trim() ?? ""),
  );
  final first = personPrenom(prenom);
  final rest = _withoutLeading(family, first);
  final tokens = rest
      .split(RegExp(r"\s+"))
      .where((part) => part.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return "";
  // Sans prénom : deux mots. Avec prénom : un seul mot de nom.
  final count = first.isEmpty ? 2 : 1;
  return tokens.take(count).join(" ");
}

/// Affiche le prénom plus un seul nom, sans postnom et sans répétition.
String displayPersonName({
  String? prenom,
  String? nom,
  String? name,
  String? postnom,
}) {
  final p = personPrenom(prenom);
  final n = personNom(nom: nom, name: name, prenom: p);
  if (p.isEmpty) return n;
  if (n.isEmpty) return p;
  return "$p $n";
}

String profileSubmitName({required String prenom, required String nom}) {
  final n = nom.trim();
  if (n.isNotEmpty) return n;
  return prenom.trim();
}
