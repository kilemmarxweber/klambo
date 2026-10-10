import "dart:async";

import "package:audioplayers/audioplayers.dart";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:klambo_messagerie/core/alert_prefs.dart";

/// Sons in-app : bip message, sonnerie reçue, bip d'appel lancé.
/// B (entrant) : sonnerie Android si possible, sinon asset WAV.
/// A (sortant) : bip « pompe » (son → repos → son), jamais un ton continu.
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  AudioPlayer? _notify;
  AudioPlayer? _ring;
  bool _ringing = false;
  bool _systemRing = false;
  bool _warmed = false;
  Future<void>? _warmInFlight;
  Timer? _ringPulseTimer;
  int _ringGeneration = 0;

  /// Durée du bip sortant, puis silence (rythme type pompe / ring-back).
  static const _outgoingBeepMs = 750;
  static const _outgoingRestMs = 1600;

  static const _androidRing = MethodChannel("klambo/background");

  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Débloque / précharge message + sonnerie (évite silence au 1er appel).
  Future<void> warmUp() async {
    if (_warmed) return;
    final inFlight = _warmInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    _warmInFlight = _doWarmUp();
    try {
      await _warmInFlight;
    } finally {
      _warmInFlight = null;
    }
  }

  Future<void> _doWarmUp() async {
    try {
      final msg = await _messagePlayer();
      await msg.setVolume(0.01);
      await msg.play(AssetSource("sounds/message.wav"), volume: 0.01);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await msg.stop();
      await msg.setVolume(1.0);

      // Prépare aussi le player d'appel — sinon le 1er appel sortant est muet.
      final ring = await _ringPlayer();
      await ring.setReleaseMode(ReleaseMode.stop);
      await ring.setVolume(0.01);
      await ring.play(AssetSource("sounds/ringtone.wav"), volume: 0.01);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await ring.stop();
      await ring.setVolume(0.85);

      _warmed = true;
      debugPrint("[sound] warmUp ok (message + ring)");
    } catch (e) {
      debugPrint("[sound] warmUp: $e");
      _warmed = false;
      await _resetNotifyPlayer();
      await _resetRingPlayer();
    }
  }

  Future<void> _playSystemCue() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (e) {
      debugPrint("[sound] SystemSound: $e");
    }
  }

  Future<AudioPlayer> _createPlayer({
    required ReleaseMode releaseMode,
    required AudioContextAndroid android,
  }) async {
    final p = AudioPlayer();
    await p.setPlayerMode(PlayerMode.mediaPlayer);
    await p.setReleaseMode(releaseMode);
    await p.setVolume(1.0);
    try {
      await p.setAudioContext(
        AudioContext(
          android: android,
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.mixWithOthers,
              AVAudioSessionOptions.duckOthers,
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint("[sound] setAudioContext: $e");
    }
    return p;
  }

  Future<AudioPlayer> _messagePlayer() async {
    final existing = _notify;
    if (existing != null) return existing;
    _notify = await _createPlayer(
      releaseMode: ReleaseMode.stop,
      android: const AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: false,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
    );
    return _notify!;
  }

  Future<AudioPlayer> _ringPlayer() async {
    final existing = _ring;
    if (existing != null) return existing;
    _ring = await _createPlayer(
      releaseMode: ReleaseMode.stop,
      android: const AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: true,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.media,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
    );
    return _ring!;
  }

  Future<void> _resetNotifyPlayer() async {
    try {
      await _notify?.dispose();
    } catch (_) {}
    _notify = null;
  }

  Future<void> _resetRingPlayer() async {
    try {
      await _ring?.dispose();
    } catch (_) {}
    _ring = null;
  }

  /// Bip nouveau message : haptic + son système + asset (si dispo).
  Future<void> playMessageTone({bool haptic = true}) async {
    if (!AlertPrefs.instance.soundsEnabled) {
      debugPrint("[sound] skipped — sounds disabled in prefs");
      return;
    }

    if (haptic) {
      try {
        await HapticFeedback.mediumImpact();
      } catch (_) {}
    }

    await _playSystemCue();

    try {
      await warmUp();
      final p = await _messagePlayer();
      await p.stop();
      await p.setVolume(1.0);
      await p.play(AssetSource("sounds/message.wav"), volume: 1.0);
      debugPrint("[sound] message asset playing");
    } catch (e) {
      debugPrint("[sound] message asset failed: $e — device cue already played");
      await _resetNotifyPlayer();
      try {
        await HapticFeedback.heavyImpact();
        await _playSystemCue();
      } catch (_) {}
    }
  }

  /// [incoming] : B reçoit l'appel (sonnerie système ou asset en boucle).
  /// Sinon A a lancé l'appel : bip avec repos (pompe).
  Future<void> startRingtone({bool incoming = false}) async {
    if (!AlertPrefs.instance.soundsEnabled) return;
    if (_ringing) return;
    _ringing = true;
    _ringPulseTimer?.cancel();
    final gen = ++_ringGeneration;

    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}

    // Débloque l'audio avant le 1er play (sinon silence au premier appel).
    await warmUp();
    if (!_ringing || gen != _ringGeneration) return;

    if (incoming && _android) {
      try {
        await _androidRing.invokeMethod<void>("startSystemRing");
        _systemRing = true;
        debugPrint("[sound] android default ringtone");
        return;
      } catch (e) {
        _systemRing = false;
        debugPrint("[sound] android default ringtone failed: $e");
      }
    }

    if (!incoming) {
      await _startOutgoingPulse(gen);
      return;
    }

    // Entrant fallback : boucle asset.
    try {
      final p = await _ringPlayer();
      if (!_ringing || gen != _ringGeneration) return;
      await p.stop();
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(1.0);
      await p.play(AssetSource("sounds/ringtone.wav"), volume: 1.0);
      debugPrint("[sound] incoming ringtone asset playing");
    } catch (e) {
      debugPrint("[sound] ringtone asset failed: $e");
      await _resetRingPlayer();
      if (!_ringing || gen != _ringGeneration) return;
      await _playSystemCue();
      _ringPulseTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!_ringing || gen != _ringGeneration) return;
        unawaited(_playSystemCue());
        unawaited(HapticFeedback.lightImpact());
      });
    }
  }

  /// Bip court → silence → bip (rythme pompe / ring-back).
  Future<void> _startOutgoingPulse(int gen) async {
    debugPrint("[sound] outgoing pulse start");
    await _runOutgoingBeepCycle(gen);
  }

  Future<void> _runOutgoingBeepCycle(int gen) async {
    if (!_ringing || gen != _ringGeneration) return;

    var played = false;
    try {
      final p = await _ringPlayer();
      if (!_ringing || gen != _ringGeneration) return;
      await p.setReleaseMode(ReleaseMode.stop);
      await p.stop();
      await p.setVolume(0.85);
      await p.play(AssetSource("sounds/ringtone.wav"), volume: 0.85);
      played = true;
      unawaited(HapticFeedback.lightImpact());
    } catch (e) {
      debugPrint("[sound] outgoing beep failed: $e");
      await _resetRingPlayer();
      await _playSystemCue();
    }

    if (!_ringing || gen != _ringGeneration) return;

    // Coupe le bip après une courte fenêtre (évite le ton continu du WAV).
    _ringPulseTimer?.cancel();
    _ringPulseTimer = Timer(const Duration(milliseconds: _outgoingBeepMs), () {
      if (!_ringing || gen != _ringGeneration) return;
      unawaited(() async {
        if (played) {
          try {
            await _ring?.stop();
          } catch (_) {}
        }
        // Repos, puis prochain bip.
        _ringPulseTimer?.cancel();
        _ringPulseTimer = Timer(
          const Duration(milliseconds: _outgoingRestMs),
          () {
            if (!_ringing || gen != _ringGeneration) return;
            unawaited(_runOutgoingBeepCycle(gen));
          },
        );
      }());
    });
  }

  Future<void> stopRingtone() async {
    _ringGeneration++;
    _ringing = false;
    _ringPulseTimer?.cancel();
    _ringPulseTimer = null;
    if (_systemRing) {
      _systemRing = false;
      try {
        await _androidRing.invokeMethod<void>("stopSystemRing");
      } catch (e) {
        debugPrint("[sound] stop android ringtone: $e");
      }
    }
    final ring = _ring;
    if (ring == null) return;
    try {
      await ring.stop();
    } catch (e) {
      debugPrint("[sound] stop ringtone failed: $e");
    }
    try {
      await ring.setReleaseMode(ReleaseMode.stop);
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stopRingtone();
    try {
      await _notify?.stop();
    } catch (_) {}
    try {
      await _notify?.dispose();
    } catch (_) {}
    try {
      await _ring?.dispose();
    } catch (_) {}
    _notify = null;
    _ring = null;
    _warmed = false;
  }
}
