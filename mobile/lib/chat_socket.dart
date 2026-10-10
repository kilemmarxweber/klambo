/// Modèle de livraison temps réel Klambo (production).
///
/// 1. **Premier plan** — WebSocket ([MessagingSocket]) : messages et signaling
///    instantanés, avec reconnexion automatique.
/// 2. **Autre app / écran verrouillé** — Foreground Service Android seulement
///    si un besoin réel l’exige (appel en cours, ou filet tant que FCM n’est
///    pas branché). Pas de reconnect WS Flutter en boucle en arrière-plan.
/// 3. **Process tué** — le backend stocke les messages et pousse via FCM ;
///    le client ne compte pas sur un socket immortel.
/// 4. **Retour dans l’app** — reconnect WS + rattrapage HTTP (`sync.resume` /
///    `link.up`) pour récupérer ce qui a manqué.
///
/// Point d’entrée documenté. Implémentation : [MessagingSocket] + [CallHub].
library;

import "package:klambo_messagerie/data/messaging_socket.dart";

export "package:klambo_messagerie/data/messaging_socket.dart"
    show MessagingSocket, CallEventHandler;

/// Alias clair pour le client WS messagerie (premier plan).
typedef ChatSocket = MessagingSocket;
