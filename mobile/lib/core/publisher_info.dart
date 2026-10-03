/// Identité éditeur officielle — affichée dans l'app et embarquée dans l'APK.
class PublisherInfo {
  PublisherInfo._();

  static const appName = "Klambo";
  static const companyLegalName = "Klambocore SARL";
  static const websiteUrl = "https://klambocore.com";
  static const supportEmail = "support@klambocore.com";
  static const packageId = "com.klambocore.klambo";
  static const downloadPath = "/app";

  /// Empreinte SHA-256 du certificat de signature release (vérification sideload).
  static const releaseSha256 =
      "B7:D8:8D:0A:61:4A:97:BD:5F:94:3D:7C:D7:D4:42:4C:7A:70:A4:DB:E4:54:06:B0:E5:B3:2A:E7:33:4D:44:C0";
}
