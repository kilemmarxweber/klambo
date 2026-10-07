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
///
/// En cas de doute (pin obsolète, preuve absente, fetch KO), on **ne coupe
/// plus l'appel** : l'audio prime. Une signature invalide avec clé à jour
/// reste journalisée mais n'interrompt plus la conversation.
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

  static String normalizePublicKey(String value) {
    try {
      var raw = value.trim().replaceAll("-", "+").replaceAll("_", "/");
      final mod = raw.length % 4;
      if (mod > 0) raw = raw.padRight(raw.length + (4 - mod), "=");
      return base64Encode(base64Decode(raw));
    } catch (_) {
      return value.trim();
    }
  }

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
      await _calls.putCallIdentity(normalizePublicKey(publicKey));
    } catch (e) {
      debugPrint("[call] identity register: $e");
    }
  }

  Future<Map<String, dynamic>> proofFor(String sdp) async {
    final pair = await CallDtls.keyPairFromSeed(await _seed());
    final proof = await CallDtls.signSdp(keyPair: pair, sdp: sdp);
    // Pas de preuve vide : elle ferait échouer le pair inutilement.
    if (proof.fingerprint.isEmpty) {
      return {};
    }
    return proof.toJson();
  }

  Future<void> verify({
    required String peerUserId,
    required String sdp,
    required dynamic dtls,
  }) async {
    final proof = DtlsProof.fromJson(dtls);
    if (proof == null) {
      debugPrint("[call] preuve DTLS absente, média conservé");
      return;
    }
    final trusted = await _trustedKey(peerUserId, proofPublicKey: proof.publicKey);
    if (trusted == null) {
      debugPrint("[call] identity absente pour $peerUserId, média conservé");
      return;
    }
    final ok = await CallDtls.verifySdp(
      sdp: sdp,
      proof: proof,
      trustedPublicKey: trusted,
    );
    if (!ok) {
      // Ne plus raccrocher : fingerprint SDP / pin / timing peuvent diverger
      // sans attaque (reinstall, web profile, ICE restart).
      debugPrint(
        "[call] identity mismatch soft-fail peer=$peerUserId "
        "(appel conservé)",
      );
      return;
    }
    final pinKey = "klambo_call_pin_$peerUserId";
    await _storage.write(key: pinKey, value: trusted);
  }

  Future<String?> _trustedKey(
    String peerUserId, {
    String? proofPublicKey,
  }) async {
    String? server = _serverKeys[peerUserId];
    if (server == null) {
      try {
        final data = await _calls.peerCallIdentity(peerUserId);
        server = data["publicKey"]?.toString();
        if (server != null && server.isNotEmpty) {
          server = normalizePublicKey(server);
          _serverKeys[peerUserId] = server;
        }
      } catch (e) {
        debugPrint("[call] identity fetch: $e");
      }
    } else {
      server = normalizePublicKey(server);
    }

    final pinKey = "klambo_call_pin_$peerUserId";
    final pinRaw = await _storage.read(key: pinKey);
    final pin = (pinRaw != null && pinRaw.isNotEmpty)
        ? normalizePublicKey(pinRaw)
        : null;

    // Rotation de clé (réinstall / nouveau navigateur) : accepter la clé
    // serveur et mettre à jour le pin — ne plus couper l'appel.
    if (pin != null && server != null && pin != server) {
      debugPrint(
        "[call] identity pin rotated for $peerUserId (ancienne clé ignorée)",
      );
      await _storage.write(key: pinKey, value: server);
      return server;
    }

    if (server != null && server.isNotEmpty) return server;
    if (pin != null && pin.isNotEmpty) return pin;

    // Dernier recours : clé portée par la preuve (premier contact, API lente).
    final fromProof = proofPublicKey == null || proofPublicKey.isEmpty
        ? null
        : normalizePublicKey(proofPublicKey);
    if (fromProof != null && fromProof.isNotEmpty) {
      debugPrint("[call] identity TOFU depuis preuve pour $peerUserId");
      _serverKeys[peerUserId] = fromProof;
      return fromProof;
    }
    return null;
  }
}
