import "package:flutter_test/flutter_test.dart";
import "package:klambo_messagerie/core/person_name.dart";

void main() {
  test("garde le prénom et un seul nom, sans répétition", () {
    expect(
      displayPersonName(
        prenom: "Joao",
        name: "Joao Simon Ngimbi Ngimbi",
      ),
      "Joao Simon",
    );
    expect(
      displayPersonName(
        prenom: "Ndombasi",
        name: "Ndombasi Ndombasi Gabriela Sofia Ba",
      ),
      "Ndombasi Gabriela",
    );
    expect(
      displayPersonName(
        prenom: "Bambi",
        name: "Bambi Filomena Bambi",
      ),
      "Bambi Filomena",
    );
    expect(
      displayPersonName(
        prenom: "Emmanuel",
        name: "Emmanuel Emmanuel Kalenda Ngulun",
      ),
      "Emmanuel Kalenda",
    );
    expect(
      displayPersonName(
        prenom: "JEAN-PIERRE",
        name: "JEAN-PIERRE LUZOLO MABIALA",
      ),
      "JEAN-PIERRE LUZOLO",
    );
    expect(
      displayPersonName(
        prenom: "Yannick",
        nom: "Kilem",
      ),
      "Yannick Kilem",
    );
    expect(
      displayPersonName(name: "Elysee ngolo ndoy"),
      "Elysee ngolo",
    );
  });
}
