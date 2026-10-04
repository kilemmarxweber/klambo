/// Quand écrire le signaling en REST, et quand sonder.
///
/// Le WebSocket porte l'offre, la réponse et les candidats ICE.
/// REST ne garde qu'un secours (socket coupé) plus l'offre déjà enregistrée
/// au `POST /calls`.
bool persistIceOnRest({required bool socketConnected}) => !socketConnected;

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

/// Décrocher depuis la notif seulement si l'appel sonne encore.
/// Le PeerConnection est créé ensuite par `acceptIncoming`.
bool shouldAutoAcceptNative({
  required bool requested,
  required bool ringingIn,
}) =>
    requested && ringingIn;
