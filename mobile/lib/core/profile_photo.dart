import "dart:typed_data";

import "package:image_picker/image_picker.dart";

class PickedProfilePhoto {
  const PickedProfilePhoto({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

/// Sélection galerie partagée (onboarding + mon profil).
Future<PickedProfilePhoto?> pickProfilePhoto() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1024,
    imageQuality: 85,
  );
  if (file == null) return null;

  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    throw Exception("Image vide, réessayez.");
  }

  final raw = file.name.trim().isNotEmpty ? file.name : "avatar.jpg";
  final lower = raw.toLowerCase();
  final filename = lower.endsWith(".png") ||
          lower.endsWith(".jpg") ||
          lower.endsWith(".jpeg") ||
          lower.endsWith(".webp")
      ? raw
      : "avatar.jpg";

  return PickedProfilePhoto(bytes: bytes, filename: filename);
}
