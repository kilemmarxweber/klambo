/// Décisions d'appel sans WebRTC : lien ICE, occupé, moment du « actif ».
enum CallIceSignal {
  checking,
  connected,
  completed,
  disconnected,
  failed,
  closed,
  other,
}

enum CallLinkAction { none, mediaUp, scheduleRestart, restartNow, endFailed }

CallIceSignal parseIceSignal(String raw) {
  final s = raw.toLowerCase();
  if (s.contains("completed")) return CallIceSignal.completed;
  if (s.contains("disconnected")) return CallIceSignal.disconnected;
  if (s.contains("connected")) return CallIceSignal.connected;
  if (s.contains("failed")) return CallIceSignal.failed;
  if (s.contains("closed")) return CallIceSignal.closed;
  if (s.contains("checking")) return CallIceSignal.checking;
  return CallIceSignal.other;
}

/// Un seul restart après échec, puis raccroché. Un succès remet le compteur à zéro.
///
/// `disconnected` / `failed` avant le premier média sont normaux (collecte ICE).
/// Les traiter comme une coupure relançait l'appel et le coupait vers 15 s.
class CallLink {
  static const maxRestarts = 1;
  static const disconnectGrace = Duration(seconds: 5);
  static const initialConnectBudget = Duration(seconds: 30);

  int restartAttempts = 0;
  bool restartInFlight = false;
  bool restartArmed = false;
  bool mediaUp = false;
  /// Vrai dès le premier ICE connecté, même si le lien retombe ensuite.
  bool hadMedia = false;

  CallLinkAction onIce(CallIceSignal signal) {
    switch (signal) {
      case CallIceSignal.connected:
      case CallIceSignal.completed:
        mediaUp = true;
        hadMedia = true;
        restartInFlight = false;
        restartArmed = false;
        restartAttempts = 0;
        return CallLinkAction.mediaUp;
      case CallIceSignal.disconnected:
        if (!hadMedia) return CallLinkAction.none;
        mediaUp = false;
        if (restartInFlight || restartArmed) return CallLinkAction.none;
        if (restartAttempts >= maxRestarts) return CallLinkAction.endFailed;
        restartArmed = true;
        return CallLinkAction.scheduleRestart;
      case CallIceSignal.failed:
        if (!hadMedia) return CallLinkAction.none;
        mediaUp = false;
        restartArmed = false;
        if (restartInFlight) return CallLinkAction.none;
        if (restartAttempts >= maxRestarts) return CallLinkAction.endFailed;
        return CallLinkAction.restartNow;
      case CallIceSignal.checking:
      case CallIceSignal.closed:
      case CallIceSignal.other:
        return CallLinkAction.none;
    }
  }

  /// Le timer de grâce (ou un échec immédiat) consomme une tentative.
  CallLinkAction takeRestart() {
    restartArmed = false;
    if (restartInFlight) return CallLinkAction.none;
    if (restartAttempts >= maxRestarts) return CallLinkAction.endFailed;
    restartAttempts += 1;
    restartInFlight = true;
    return CallLinkAction.restartNow;
  }

  void disarm() {
    restartArmed = false;
    restartInFlight = false;
  }

  void reset() {
    restartAttempts = 0;
    restartInFlight = false;
    restartArmed = false;
    mediaUp = false;
    hadMedia = false;
  }

  /// Changement Wi-Fi / données pendant que le média est négocié ou établi.
  CallLinkAction onNetworkChanged({required bool mediaPhase}) {
    if (!mediaPhase || !hadMedia) return CallLinkAction.none;
    if (restartInFlight || restartArmed) return CallLinkAction.none;
    if (restartAttempts >= maxRestarts) return CallLinkAction.none;
    restartArmed = true;
    return CallLinkAction.scheduleRestart;
  }
}

/// Offre d'un autre appel pendant qu'on est déjà en ligne.
bool shouldReplyBusy({required bool inCall, required bool sameCall}) {
  return inCall && !sameCall;
}

/// Le SDP de réponse ne signifie pas que l'audio passe.
bool markActiveOnAnswer({required bool mediaAlreadyUp}) => mediaAlreadyUp;
