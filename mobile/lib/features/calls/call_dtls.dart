import "dart:convert";

import "package:cryptography/cryptography.dart";

/// Empreintes DTLS triées, pour signer exactement le même texte des deux côtés.
String canonicalDtlsFingerprints(String sdp) {
  final found = RegExp(r"a=fingerprint:\S+\s+([0-9A-Fa-f:]+)")
      .allMatches(sdp)
      .map((m) => m.group(1)!.toUpperCase())
      .toSet()
      .toList()
    ..sort();
  return found.join("|");
}

class DtlsProof {
  const DtlsProof({
    required this.fingerprint,
    required this.publicKey,
    required this.signature,
  });

  final String fingerprint;
  final String publicKey;
  final String signature;

  Map<String, dynamic> toJson() => {
        "fingerprint": fingerprint,
        "publicKey": publicKey,
        "signature": signature,
      };

  static DtlsProof? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final fingerprint = map["fingerprint"]?.toString() ?? "";
    final publicKey = map["publicKey"]?.toString() ?? "";
    final signature = map["signature"]?.toString() ?? "";
    if (fingerprint.isEmpty || publicKey.isEmpty || signature.isEmpty) {
      return null;
    }
    return DtlsProof(
      fingerprint: fingerprint,
      publicKey: publicKey,
      signature: signature,
    );
  }
}

class CallDtls {
  static final _ed = Ed25519();

  static Future<SimpleKeyPair> keyPairFromSeed(List<int> seed) {
    return _ed.newKeyPairFromSeed(seed);
  }

  static Future<List<int>> newSeed() async {
    final pair = await _ed.newKeyPair();
    return pair.extractPrivateKeyBytes();
  }

  static Future<String> publicKeyBase64(SimpleKeyPair pair) async {
    final pub = await pair.extractPublicKey();
    return base64Encode(pub.bytes);
  }

  static Future<DtlsProof> signSdp({
    required SimpleKeyPair keyPair,
    required String sdp,
  }) async {
    final fingerprint = canonicalDtlsFingerprints(sdp);
    final signature = await _ed.sign(
      utf8.encode(fingerprint),
      keyPair: keyPair,
    );
    return DtlsProof(
      fingerprint: fingerprint,
      publicKey: await publicKeyBase64(keyPair),
      signature: base64Encode(signature.bytes),
    );
  }

  static String _normKey(String value) {
    try {
      var raw = value.trim().replaceAll("-", "+").replaceAll("_", "/");
      final mod = raw.length % 4;
      if (mod > 0) raw = raw.padRight(raw.length + (4 - mod), "=");
      return base64Encode(base64Decode(raw));
    } catch (_) {
      return value.trim();
    }
  }

  /// Vrai si la preuve correspond au SDP et à la clé publique déjà liée au compte.
  static Future<bool> verifySdp({
    required String sdp,
    required DtlsProof proof,
    required String trustedPublicKey,
  }) async {
    if (_normKey(proof.publicKey) != _normKey(trustedPublicKey)) return false;
    final fingerprint = canonicalDtlsFingerprints(sdp);
    // SDP sans empreinte (offre incomplète) : vérifier seulement la signature
    // sur l'empreinte déclarée dans la preuve.
    final expected =
        fingerprint.isEmpty ? proof.fingerprint : fingerprint;
    if (expected.isEmpty) return false;
    if (fingerprint.isNotEmpty && fingerprint != proof.fingerprint) {
      return false;
    }
    try {
      final publicKey = SimplePublicKey(
        base64Decode(_normKey(trustedPublicKey)),
        type: KeyPairType.ed25519,
      );
      return await _ed.verify(
        utf8.encode(expected),
        signature: Signature(
          base64Decode(proof.signature),
          publicKey: publicKey,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
