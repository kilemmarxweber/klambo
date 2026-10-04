import "dart:convert";

import "package:flutter/foundation.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:klambo_messagerie/data/calls_repository.dart";
import "package:klambo_messagerie/features/calls/call_dtls.dart";

class CallIdentityException implements Exception {
  CallIdentityException(this.code);
  final String code;
  @override
  String toString() => code;
}

/// Clé d'identité locale, publication sur le compte, vérification du pair.
class CallIdentity {
  CallIdentity({
    required CallsRepository calls,
    FlutterSecureStorage? storage,
  })  : _calls = calls,
        _storage = storage ?? const FlutterSecureStorage();

  static const _seedKey = "klambo_call_identity_seed";

  final CallsRepository _calls;
  final FlutterSecureStorage _storage;
  final Map<String, String> _serverKeys = {};

  Future<List<int>> _seed() async {
    final existing = await _storage.read(key: _seedKey);
    if (existing != null && existing.isNotEmpty) {
      return base64Decode(existing);
    }
    final seed = await CallDtls.newSeed();
    await _storage.write(key: _seedKey, value: base64Encode(seed));
    return seed;
  }

  Future<void> ensureRegistered() async {
    try {
      final pair = await CallDtls.keyPairFromSeed(await _seed());
      final publicKey = await CallDtls.publicKeyBase64(pair);
      await _calls.putCallIdentity(publicKey);
    } catch (e) {
      debugPrint("[call] identity register: $e");
    }
  }

  Future<Map<String, dynamic>> proofFor(String sdp) async {
    final pair = await CallDtls.keyPairFromSeed(await _seed());
    final proof = await CallDtls.signSdp(keyPair: pair, sdp: sdp);
    return proof.toJson();
  }

  Future<void> verify({
    required String peerUserId,
    required String sdp,
    required dynamic dtls,
  }) async {
    final proof = DtlsProof.fromJson(dtls);
    if (proof == null) {
      throw CallIdentityException("identity");
    }
    final trusted = await _trustedKey(peerUserId);
    if (trusted == null) {
      throw CallIdentityException("identity");
    }
    final ok = await CallDtls.verifySdp(
      sdp: sdp,
      proof: proof,
      trustedPublicKey: trusted,
    );
    if (!ok) throw CallIdentityException("identity");
    final pinKey = "klambo_call_pin_$peerUserId";
    final pin = await _storage.read(key: pinKey);
    if (pin == null) {
      await _storage.write(key: pinKey, value: trusted);
    }
  }

  Future<String?> _trustedKey(String peerUserId) async {
    String? server = _serverKeys[peerUserId];
    if (server == null) {
      try {
        final data = await _calls.peerCallIdentity(peerUserId);
        server = data["publicKey"]?.toString();
        if (server != null && server.isNotEmpty) {
          _serverKeys[peerUserId] = server;
        }
      } catch (e) {
        debugPrint("[call] identity fetch: $e");
      }
    }
    final pin = await _storage.read(key: "klambo_call_pin_$peerUserId");
    if (pin != null && server != null && pin != server) {
      throw CallIdentityException("identity");
    }
    return server ?? pin;
  }
}
