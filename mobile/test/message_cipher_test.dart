import "package:flutter_test/flutter_test.dart";
import "package:klambo_messagerie/features/crypto/message_cipher.dart";

void main() {
  test("les deux téléphones lisent le message, un tiers non", () async {
    final alice = await MessageCipher.keyPairFromSeed(List<int>.filled(32, 3));
    final bob = await MessageCipher.keyPairFromSeed(List<int>.filled(32, 9));
    final eve = await MessageCipher.keyPairFromSeed(List<int>.filled(32, 11));
    final bobPub = await MessageCipher.publicKeyBase64(bob);

    const clair = "Bonjour Milo";
    final envelope = await MessageCipher.seal(
      plaintext: clair,
      sender: alice,
      recipientPublicKey: bobPub,
    );

    expect(MessageCipher.isEnvelope(envelope), isTrue);
    expect(envelope.contains(clair), isFalse);
    expect(await MessageCipher.open(envelope: envelope, keyPair: bob), clair);
    expect(await MessageCipher.open(envelope: envelope, keyPair: alice), clair);
    expect(await MessageCipher.open(envelope: envelope, keyPair: eve), isNull);
  });

  test("un ciphertext modifié est refusé", () async {
    final alice = await MessageCipher.keyPairFromSeed(List<int>.filled(32, 4));
    final bob = await MessageCipher.keyPairFromSeed(List<int>.filled(32, 5));
    final envelope = await MessageCipher.seal(
      plaintext: "secret",
      sender: alice,
      recipientPublicKey: await MessageCipher.publicKeyBase64(bob),
    );
    final chars = envelope.split("");
    final last = chars.length - 1;
    chars[last] = chars[last] == "A" ? "B" : "A";
    expect(
      await MessageCipher.open(envelope: chars.join(), keyPair: bob),
      isNull,
    );
  });

  test("une clé publique fait 32 octets", () async {
    final pair = await MessageCipher.keyPairFromSeed(List<int>.filled(32, 1));
    final encoded = await MessageCipher.publicKeyBase64(pair);
    expect(
      MessageCipher.publicKeyFromBase64(encoded).bytes,
      hasLength(32),
    );
    expect(
      () => MessageCipher.publicKeyFromBase64("YQ=="),
      throwsFormatException,
    );
  });
}
