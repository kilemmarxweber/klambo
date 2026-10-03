/// Prénom et nom restent séparés : aucune concaténation avec le postnom.
String personPrenom(String? prenom) => prenom?.trim() ?? "";

String personNom({String? nom, String? name}) {
  final family = nom?.trim() ?? "";
  if (family.isNotEmpty) return family;
  return name?.trim() ?? "";
}

/// Affiche prénom + nom, sans postnom. Si [name] contient déjà le prénom, il n’est pas répété.
String displayPersonName({
  String? prenom,
  String? nom,
  String? name,
}) {
  final p = personPrenom(prenom);
  final n = personNom(nom: nom, name: name);
  if (p.isEmpty) return n;
  if (n.isEmpty) return p;
  if (n.toLowerCase().startsWith("${p.toLowerCase()} ") ||
      n.toLowerCase() == p.toLowerCase()) {
    return n;
  }
  return "$p $n";
}

String profileSubmitName({required String prenom, required String nom}) {
  final n = nom.trim();
  if (n.isNotEmpty) return n;
  return prenom.trim();
}
