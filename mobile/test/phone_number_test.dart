import "package:flutter_test/flutter_test.dart";
import "package:klambo_messagerie/core/phone_number.dart";

void main() {
  test("reprend le numéro collé au nom", () {
    expect(findPhoneInText("+243 811 727 829"), "+243 811 727 829");
    expect(
      findPhoneInText("+243 811 727 829 Kanzal"),
      "+243 811 727 829",
    );
    expect(textWithoutPhone("+243 811 727 829 Kanzal"), "Kanzal");
    expect(textWithoutPhone("+243 811 727 829"), "");
    expect(textWithoutPhone("yannick"), "yannick");
    expect(findPhoneInText("Kanzal"), isNull);
  });

  test("affiche le téléphone du compte à côté du prénom et du nom", () {
    expect(
      accountTelephone({
        "prenom": "yannick",
        "nom": "kilem",
        "name": "Yannick Kilem",
        "telephone": "+243844952966",
      }),
      "+243844952966",
    );
    expect(
      accountTelephone({
        "prenom": "yannick",
        "nom": "kilem",
        "user": {"telephone": "+243 844 952 966"},
      }),
      "+243844952966",
    );
  });

  test("lit le téléphone du user dans items, à côté du rôle", () {
    expect(
      phoneFromApiPayload(
        {
          "items": [
            {
              "prenom": "Obed",
              "nom": "Tshimanga",
              "roleLabel": "Support établissement",
              "user": {"id": "u1", "telephone": "+243844952966"},
            },
          ],
        },
        userId: "u1",
      ),
      "+243844952966",
    );
    expect(
      phoneFromApiPayload(
        {
          "items": [
            {
              "userId": "u1",
              "prenom": "Obed",
              "roleLabel": "Support établissement",
              "phoneNumber": "+243 811 727 829",
            },
          ],
        },
        userId: "u1",
      ),
      "+243811727829",
    );
  });

  test("lit le numéro dans le prénom quand le champ téléphone est vide", () {
    expect(
      extractPhoneNumber({
        "prenom": "+243 811 727 829",
        "name": "Kanzal",
        "roleLabel": "Support établissement",
      }),
      "+243 811 727 829",
    );
    expect(
      extractPhoneNumber({
        "user": {"name": "+243 811 727 829 Kanzal"},
      }),
      "+243 811 727 829",
    );
  });
}
