import "package:dio/dio.dart";
import "package:flutter/foundation.dart";
import "package:gal/gal.dart";
import "package:klambo_messagerie/core/gallery_save_stub.dart"
    if (dart.library.html) "package:klambo_messagerie/core/gallery_save_web.dart"
    as web_dl;

/// Enregistre une image dans la galerie du device (Android/iOS)
/// ou la télécharge via le navigateur (web).
Future<void> saveImageToDeviceGallery({
  required Uint8List bytes,
  String name = "klambo",
}) async {
  if (bytes.isEmpty) throw Exception("Image vide");

  final safeName = name
      .replaceAll(RegExp(r"[^\w\-]+"), "_")
      .replaceAll(RegExp(r"_+"), "_");
  final base = safeName.isEmpty ? "klambo" : safeName;

  if (kIsWeb) {
    await web_dl.downloadBytesInBrowser(bytes, "$base.jpg");
    return;
  }

  final hasAccess = await Gal.hasAccess();
  if (!hasAccess) {
    final granted = await Gal.requestAccess();
    if (!granted) throw Exception("Permission galerie refusée");
  }

  await Gal.putImageBytes(bytes, name: base);
}

/// Télécharge depuis [url] (ou utilise [localBytes]) puis enregistre.
Future<void> saveImageUrlToDeviceGallery({
  required String? url,
  String name = "klambo",
  Uint8List? localBytes,
}) async {
  late final Uint8List bytes;
  if (localBytes != null && localBytes.isNotEmpty) {
    bytes = localBytes;
  } else if (url != null && url.isNotEmpty) {
    final res = await Dio().get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = res.data;
    if (data == null || data.isEmpty) {
      throw Exception("Téléchargement échoué");
    }
    bytes = Uint8List.fromList(data);
  } else {
    throw Exception("Image indisponible");
  }

  await saveImageToDeviceGallery(bytes: bytes, name: name);
}
