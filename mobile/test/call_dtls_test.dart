import "dart:convert";
import "dart:typed_data";

import "package:cryptography/cryptography.dart";
import "package:flutter_test/flutter_test.dart";
import "package:klambo_messagerie/features/calls/call_dtls.dart";

List<int> _hex(String value) {
  final out = Uint8List(value.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(value.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _hexOf(List<int> bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, "0")).join();
}

void main() {
  test("empreintes DTLS canoniques, uniques et triées", () {
    const sdp = """
v=0
a=fingerprint:sha-256 AA:BB:CC
a=fingerprint:sha-256 11:22
a=fingerprint:sha-256 aa:bb:cc
""";
    expect(canonicalDtlsFingerprints(sdp), "11:22|AA:BB:CC");
  });

  test("la signature couvre l'empreinte et refuse un SDP modifié", () async {
    final pair = await CallDtls.keyPairFromSeed(List<int>.filled(32, 7));
    const sdp = "a=fingerprint:sha-256 AB:CD\r\n";
    final proof = await CallDtls.signSdp(keyPair: pair, sdp: sdp);
    final trusted = proof.publicKey;
    expect(
      await CallDtls.verifySdp(sdp: sdp, proof: proof, trustedPublicKey: trusted),
      isTrue,
    );
    expect(
      await CallDtls.verifySdp(
        sdp: "a=fingerprint:sha-256 FF:FF\r\n",
        proof: proof,
        trustedPublicKey: trusted,
      ),
      isFalse,
    );
    final other = await CallDtls.keyPairFromSeed(List<int>.filled(32, 9));
    final otherKey = await CallDtls.publicKeyBase64(other);
    expect(
      await CallDtls.verifySdp(sdp: sdp, proof: proof, trustedPublicKey: otherKey),
      isFalse,
    );
  });

  test("vecteur Ed25519 RFC 8032 (message vide)", () async {
    final seed = _hex(
      "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
    );
    final pair = await CallDtls.keyPairFromSeed(seed);
    final pub = await pair.extractPublicKey();
    expect(
      _hexOf(pub.bytes),
      "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
    );
    final signature = await Ed25519().sign(
      utf8.encode(""),
      keyPair: pair,
    );
    expect(
      _hexOf(signature.bytes),
      "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155"
          "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
    );
  });
}
