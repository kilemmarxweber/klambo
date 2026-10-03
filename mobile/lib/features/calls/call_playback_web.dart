import "dart:js_interop";
import "dart:js_interop_unsafe";

/// Baisse uniquement les éléments audio WebRTC (pas les sons de l'app).
void applyCallPlaybackVolume(double volume) {
  final document = globalContext["document"] as JSObject?;
  if (document == null) return;
  final nodes = document.callMethod<JSObject>(
    "querySelectorAll".toJS,
    "audio".toJS,
  );
  final length = (nodes["length"] as JSNumber).toDartInt;
  final level = volume.clamp(0.0, 1.0).toJS;
  for (var i = 0; i < length; i++) {
    final el = nodes.callMethod<JSObject?>("item".toJS, i.toJS);
    if (el == null) continue;
    final id = (el["id"] as JSString?)?.toDart ?? "";
    if (!id.startsWith("audio_RTCVideoRenderer-")) continue;
    final muted = (el["muted"] as JSBoolean?)?.toDart ?? false;
    if (muted) continue;
    el["volume"] = level;
  }
}
