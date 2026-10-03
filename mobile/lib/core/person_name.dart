/// Prénom et nom restent séparés : le postnom n'est pas affiché.
String personPrenom(String? prenom) => prenom?.trim() ?? "";

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

/// Un seul des deux : [nom] s'il est rempli, sinon [name]. Jamais les deux.
String personNom({
  String? nom,
  String? name,
  String? prenom,
  String? postnom,
}) {
  final family = (nom?.trim().isNotEmpty ?? false)
      ? nom!.trim()
      : (name?.trim() ?? "");
  return _withoutLeading(family, personPrenom(prenom));
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
