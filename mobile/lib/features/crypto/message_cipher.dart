import "dart:convert";
import "dart:math";
import "dart:typed_data";

import "package:cryptography/cryptography.dart";

/// Enveloppe `k1.` : X25519 + AES-GCM. La clé privée ne quitte pas l'appareil.
class MessageCipher {
  MessageCipher._();

  static const prefix = "k1.";
  static const version = 1;
  static const publicKeyLength = 32;
  static const nonceLength = 12;
  static const macLength = 16;
  static const maxEnvelopeLength = 22000;

  static final _envelope = RegExp(r"^k1\.[A-Za-z0-9_-]{120,}$");
  static final _x25519 = X25519();
  static final _aes = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _salt = utf8.encode("klambo-message-v1");

  static bool isEnvelope(String value) {
    final trimmed = value.trim();
    return trimmed.length <= maxEnvelopeLength && _envelope.hasMatch(trimmed);
  }

  static Future<List<int>> newSeed() async {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256));
  }

  static Future<SimpleKeyPair> keyPairFromSeed(List<int> seed) {
    return _x25519.newKeyPairFromSeed(seed);
  }

  static Future<String> publicKeyBase64(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  static SimplePublicKey publicKeyFromBase64(String value) {
    final bytes = base64Decode(value.trim());
    if (bytes.length != publicKeyLength) {
      throw const FormatException("Clé publique de message invalide.");
    }
    return SimplePublicKey(bytes, type: KeyPairType.x25519);
  }

  /// Chiffre pour le destinataire. L'expéditeur peut relire avec sa clé privée.
  static Future<String> seal({
    required String plaintext,
    required SimpleKeyPair sender,
    required String recipientPublicKey,
  }) async {
    final senderPub = await sender.extractPublicKey();
    final recipient = publicKeyFromBase64(recipientPublicKey);
    final box = await _encrypt(
      plaintext: plaintext,
      sender: sender,
      senderPub: senderPub.bytes,
      recipientPub: recipient.bytes,
      remote: recipient,
    );
    if (box.length > maxEnvelopeLength) {
      throw const FormatException("Message trop long pour le chiffrement.");
    }
    return box;
  }

  /// Ouvre une enveloppe adressée à cette clé, ou renvoyée par elle.
  /// `null` si le MAC ne correspond pas.
  static Future<String?> open({
    required String envelope,
    required SimpleKeyPair keyPair,
  }) async {
    if (!isEnvelope(envelope)) return envelope;
    final bytes = _decode(envelope.trim().substring(prefix.length));
    if (bytes.length < 1 + publicKeyLength * 2 + nonceLength + macLength) {
      return null;
    }
    if (bytes[0] != version) return null;
    var o = 1;
    final senderPub = bytes.sublist(o, o + publicKeyLength);
    o += publicKeyLength;
    final recipientPub = bytes.sublist(o, o + publicKeyLength);
    o += publicKeyLength;
    final nonce = bytes.sublist(o, o + nonceLength);
    o += nonceLength;
    final mac = bytes.sublist(o, o + macLength);
    o += macLength;
    final cipher = bytes.sublist(o);

    final mine = await keyPair.extractPublicKey();
    final mineBytes = mine.bytes;
    final List<int> remoteBytes;
    if (_same(mineBytes, recipientPub)) {
      remoteBytes = senderPub;
    } else if (_same(mineBytes, senderPub)) {
      remoteBytes = recipientPub;
    } else {
      return null;
    }

    try {
      final clear = await _aes.decrypt(
        SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
        secretKey: await _aesKey(
          keyPair: keyPair,
          remote: SimplePublicKey(remoteBytes, type: KeyPairType.x25519),
        ),
        aad: <int>[...senderPub, ...recipientPub],
      );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  static Future<String> _encrypt({
    required String plaintext,
    required SimpleKeyPair sender,
    required List<int> senderPub,
    required List<int> recipientPub,
    required SimplePublicKey remote,
  }) async {
    final box = await _aes.encrypt(
      utf8.encode(plaintext),
      secretKey: await _aesKey(keyPair: sender, remote: remote),
      aad: <int>[...senderPub, ...recipientPub],
    );
    final packed = Uint8List(
      1 +
          publicKeyLength * 2 +
          box.nonce.length +
          box.mac.bytes.length +
          box.cipherText.length,
    );
    var o = 0;
    packed[o++] = version;
    packed.setAll(o, senderPub);
    o += senderPub.length;
    packed.setAll(o, recipientPub);
    o += recipientPub.length;
    packed.setAll(o, box.nonce);
    o += box.nonce.length;
    packed.setAll(o, box.mac.bytes);
    o += box.mac.bytes.length;
    packed.setAll(o, box.cipherText);
    return "$prefix${_encode(packed)}";
  }

  static Future<SecretKey> _aesKey({
    required SimpleKeyPair keyPair,
    required SimplePublicKey remote,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: remote,
    );
    return _hkdf.deriveKey(secretKey: shared, nonce: _salt);
  }

  static String _encode(List<int> bytes) =>
      base64UrlEncode(bytes).replaceAll("=", "");

  static Uint8List _decode(String value) {
    final pad = (4 - value.length % 4) % 4;
    return base64Url.decode("$value${"=" * pad}");
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
