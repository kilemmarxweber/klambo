/// Quand écrire le signaling en REST, et quand sonder.
///
/// Le WebSocket porte l'offre, la réponse et les candidats ICE.
/// REST garde les candidats publics (autre réseau) et sert de secours
/// si le socket est coupé. L'offre initiale est déjà au `POST /calls`.
/// Candidat joignable hors du réseau local (STUN ou relais).
bool isPublicIceCandidate(String candidate) {
  return candidate.contains(" typ srflx") || candidate.contains(" typ relay");
}

/// Les candidats locaux restent sur le WebSocket.
/// Les candidats publics sont aussi écrits en REST : un paquet perdu
/// empêche l'appel dès que les téléphones ne sont plus sur le même routeur.
bool persistIceOnRest({
  required bool socketConnected,
  required String candidate,
}) {
  if (!socketConnected) return true;
  return isPublicIceCandidate(candidate);
}

bool persistOfferSnapshotOnRest({required bool socketConnected}) =>
    !socketConnected;

bool shouldPollCalls({required bool socketConnected}) => !socketConnected;

/// Secours HTTP des appels. Rien tant que le WebSocket est vivant.
/// En appel, un pull court rattrape l'ICE. Au repos, un intervalle long
/// suffit pour une sonnerie manquée, sans charger l'historique à chaque tick.
Duration? callFallbackDelay({
  required bool socketConnected,
  required bool inCall,
}) {
  if (socketConnected) return null;
  if (inCall) return const Duration(seconds: 3);
  return const Duration(seconds: 15);
}

bool shouldResendOffer({required bool acked, required bool ringingOut}) =>
    ringingOut && !acked;

/// Le pair a déjà terminé l'appel côté serveur (raccroché, refusé, manqué).
bool remoteCallFinished(String? status) {
  switch (status) {
    case "ENDED":
    case "REJECTED":
    case "MISSED":
      return true;
    default:
      return false;
  }
}

/// Décrocher depuis la notif seulement si l'appel sonne encore.
/// Le PeerConnection (micro + answer locaux) est préchauffé dès `ringingIn` ;
/// `acceptIncoming` envoie surtout le signal `call.answer`.
bool shouldAutoAcceptNative({
  required bool requested,
  required bool ringingIn,
}) =>
    requested && ringingIn;
