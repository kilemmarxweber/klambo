import "dart:typed_data";

/// Téléchargement navigateur (web uniquement).
Future<void> downloadBytesInBrowser(Uint8List bytes, String filename) async {
  throw UnsupportedError("Téléchargement navigateur non disponible");
}
