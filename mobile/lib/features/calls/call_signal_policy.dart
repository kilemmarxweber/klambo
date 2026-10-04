/// Quand écrire le signaling en REST, et quand sonder.
///
/// Le WebSocket porte l'offre, la réponse et les candidats ICE.
/// REST ne garde qu'un secours (socket coupé) plus l'offre déjà enregistrée
/// au `POST /calls`.
bool persistIceOnRest({required bool socketConnected}) => !socketConnected;

bool persistOfferSnapshotOnRest({required bool socketConnected}) =>
    !socketConnected;

bool shouldPollCalls({required bool socketConnected}) => !socketConnected;

bool shouldResendOffer({required bool acked, required bool ringingOut}) =>
    ringingOut && !acked;

/// Décrocher depuis la notif seulement si l'appel sonne encore.
/// Le PeerConnection est créé ensuite par `acceptIncoming`.
bool shouldAutoAcceptNative({
  required bool requested,
  required bool ringingIn,
}) =>
    requested && ringingIn;
