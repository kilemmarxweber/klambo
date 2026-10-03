import "call_playback_stub.dart"
    if (dart.library.html) "call_playback_web.dart" as impl;

/// Volume de lecture WebRTC. Sur mobile natif, c'est un no-op :
/// le routage oreillette / haut-parleur suffit.
void applyCallPlaybackVolume(double volume) =>
    impl.applyCallPlaybackVolume(volume);
