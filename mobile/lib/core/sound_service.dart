import "dart:async";

import "package:audioplayers/audioplayers.dart";
import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:klambo_messagerie/core/alert_prefs.dart";

/// Sons in-app : bip message, sonnerie reçue, bip d'appel lancé.
/// B (entrant) : sonnerie des réglages Android. A (sortant) : bip continu.
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  AudioPlayer? _notify;
  AudioPlayer? _ring;
  bool _ringing = false;
  bool _systemRing = false;
  bool _warmed = false;
  Timer? _ringFallbackTimer;

  static const _androidRing = MethodChannel("klambo/background");

  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Débloque / précharge le lecteur qui servira aux alertes automatiques.
  /// Le même player est réutilisé : un lecteur jetable ne débloque pas le suivant.
  Future<void> warmUp() async {
    if (_warmed) return;
    try {
      final p = await _messagePlayer();
      await p.setVolume(0.01);
      await p.play(AssetSource("sounds/message.wav"), volume: 0.01);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await p.stop();
      await p.setVolume(1.0);
      _warmed = true;
      debugPrint("[sound] warmUp ok");
    } catch (e) {
      debugPrint("[sound] warmUp: $e");
      _warmed = false;
      await _resetNotifyPlayer();
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
    // mediaPlayer = plus fiable pour les WAV assets que lowLatency.
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
        // media : audible au premier plan. usage "notification" est souvent
        // coupé par Android quand l'app est ouverte (le test au tap, lui, passe).
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
      releaseMode: ReleaseMode.loop,
      android: const AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: true,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.notificationRingtone,
        audioFocus: AndroidAudioFocus.gain,
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

    // 1) Cue système device (toujours tenter — indépendant des assets).
    await _playSystemCue();

    // 2) Asset Klambo (meilleur rendu si le fichier charge).
    try {
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

  /// [incoming] : B reçoit l'appel (sonnerie des réglages).
  /// Sinon A a lancé l'appel (bip continu).
  Future<void> startRingtone({bool incoming = false}) async {
    if (!AlertPrefs.instance.soundsEnabled) return;
    if (_ringing) return;
    _ringing = true;
    _ringFallbackTimer?.cancel();

    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}

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

    if (incoming) {
      await _playSystemCue();
      _ringFallbackTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!_ringing) return;
        unawaited(_playSystemCue());
        unawaited(HapticFeedback.lightImpact());
      });
      return;
    }

    var assetOk = false;
    try {
      final p = await _ringPlayer();
      await p.stop();
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(0.85);
      await p.play(AssetSource("sounds/ringtone.wav"), volume: 0.85);
      assetOk = true;
      debugPrint("[sound] outgoing beep playing");
    } catch (e) {
      debugPrint("[sound] outgoing beep failed: $e");
      await _resetRingPlayer();
    }

    // Web / bureau : si l’asset échoue, répéter le bip système.
    if (!assetOk) {
      await _playSystemCue();
      _ringFallbackTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!_ringing) return;
        unawaited(_playSystemCue());
        unawaited(HapticFeedback.lightImpact());
      });
    }
  }

  Future<void> stopRingtone() async {
    _ringing = false;
    _ringFallbackTimer?.cancel();
    _ringFallbackTimer = null;
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
      await ring.setReleaseMode(ReleaseMode.release);
    } catch (_) {}
  }

  Future<void> dispose() async {
    _ringing = false;
    _ringFallbackTimer?.cancel();
    _ringFallbackTimer = null;
    if (_systemRing) {
      _systemRing = false;
      try {
        await _androidRing.invokeMethod<void>("stopSystemRing");
      } catch (_) {}
    }
    try {
      await _notify?.stop();
    } catch (_) {}
    try {
      await _ring?.stop();
    } catch (_) {}
    try {
      await _notify?.dispose();
    } catch (_) {}
    try {
      await _ring?.dispose();
    } catch (_) {}
    _notify = null;
    _ring = null;
  }
}
