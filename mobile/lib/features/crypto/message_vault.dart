import "dart:convert";

import "package:cryptography/cryptography.dart";
import "package:flutter/foundation.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:klambo_messagerie/data/api_client.dart";
import "package:klambo_messagerie/features/crypto/message_cipher.dart";

const sealedMessagePlaceholder = "Message chiffré";

/// Clé privée dans le coffre du téléphone. Seule la clé publique est publiée.
class MessageVault {
  MessageVault({
    required ApiClient api,
    FlutterSecureStorage? storage,
  })  : _api = api,
        _storage = storage ?? const FlutterSecureStorage();

  static const _seedKey = "klambo_message_identity_seed";

  final ApiClient _api;
  final FlutterSecureStorage _storage;
  final Map<String, String> _peerKeys = {};
  Future<void>? _registering;

  Future<List<int>> _seed() async {
    final existing = await _storage.read(key: _seedKey);
    if (existing != null && existing.isNotEmpty) {
      return base64Decode(existing);
    }
    final seed = await MessageCipher.newSeed();
    await _storage.write(key: _seedKey, value: base64Encode(seed));
    return seed;
  }

  Future<SimpleKeyPair> _keyPair() async {
    return MessageCipher.keyPairFromSeed(await _seed());
  }

  Future<void> ensureRegistered() {
    return _registering ??= _publish().catchError((Object error) {
      _registering = null;
      debugPrint("[e2ee] identity: $error");
    });
  }

  Future<void> _publish() async {
    final publicKey = await MessageCipher.publicKeyBase64(await _keyPair());
    await _api.postJson(
      "/messages/identity",
      data: {"publicKey": publicKey},
    );
  }

  /// Chiffre un direct si le correspondant a une clé. Sinon le texte reste clair
  /// (l'autre appareil n'a pas encore de clé). Un échec réseau ne repasse pas en clair.
  Future<String> seal(String plaintext, {required String peerUserId}) async {
    if (MessageCipher.isEnvelope(plaintext)) return plaintext;
    await ensureRegistered();
    final peer = await _peerPublicKey(peerUserId);
    if (peer == null) return plaintext;
    return MessageCipher.seal(
      plaintext: plaintext,
      sender: await _keyPair(),
      recipientPublicKey: peer,
    );
  }

  Future<String> open(String body) async {
    if (!MessageCipher.isEnvelope(body)) return body;
    try {
      final clear = await MessageCipher.open(
        envelope: body,
        keyPair: await _keyPair(),
      );
      if (clear == null || clear.isEmpty) return sealedMessagePlaceholder;
      return clear;
    } catch (error) {
      debugPrint("[e2ee] open: $error");
      return sealedMessagePlaceholder;
    }
  }

  Future<String?> _peerPublicKey(String userId) async {
    final cached = _peerKeys[userId];
    if (cached != null) return cached;
    try {
      final data = await _api.getJson("/messages/identity/$userId");
      final key = data["publicKey"]?.toString();
      if (key == null || key.isEmpty) return null;
      _peerKeys[userId] = key;
      return key;
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }
}

/// L'autre personne d'une conversation directe, pour chiffrer vers sa clé.
String? directPeerUserId(Map item, String? myId) {
  if (item["type"]?.toString() != "DIRECT" || myId == null || myId.isEmpty) {
    return null;
  }
  final participants = item["participants"];
  if (participants is! List) return null;
  for (final raw in participants) {
    if (raw is! Map) continue;
    final id = raw["userId"]?.toString();
    if (id != null && id.isNotEmpty && id != myId) return id;
  }
  return null;
}
