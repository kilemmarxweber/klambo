import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:klambo_messagerie/data/calls_repository.dart";
import "package:klambo_messagerie/data/messaging_socket.dart";
import "package:klambo_messagerie/features/calls/call_playback.dart";

enum CallPhase { idle, ringingOut, ringingIn, connecting, active, ended }

class ActiveCall {
  ActiveCall({
    required this.callId,
    required this.organizationId,
    required this.peerUserId,
    required this.kind,
    required this.isCaller,
    this.peerName,
    this.conversationId,
  });

  final String callId;
  final String organizationId;
  final String peerUserId;
  final String kind; // AUDIO | VIDEO
  final bool isCaller;
  final String? peerName;
  final String? conversationId;
}

/// Contrôleur WebRTC 1:1 (appel visite) — signaling via MessagingSocket.
class CallController extends ChangeNotifier {
  CallController({
    required CallsRepository calls,
    required MessagingSocket socket,
    required this.localUserId,
  })  : _calls = calls,
        _socket = socket {
    _socket.onCallEvent = _onSignal;
  }

  final CallsRepository _calls;
  final MessagingSocket _socket;
  final String localUserId;
  void Function(ActiveCall call)? onIncomingRing;

  CallPhase phase = CallPhase.idle;
  ActiveCall? active;
  String? error;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  bool _renderersReady = false;
  bool _disposed = false;
  bool _ending = false;
  bool micMuted = false;
  bool camOff = false;
  /// Coupé par défaut : volume de conversation. Activé : son fort.
  bool speakerOn = false;
  final List<RTCIceCandidate> _pendingRemoteIce = [];
  final Set<String> _appliedRemoteIce = {};
  bool _answerApplied = false;
  Timer? _offerResendTimer;
  Timer? _ringTimeout;
  Map<String, dynamic>? _lastOfferPayload;

  bool get isBusy =>
      phase != CallPhase.idle && phase != CallPhase.ended;

  bool get isDisposed => _disposed;

  void setStatusHint(String? message) {
    error = message;
    _safeNotify();
  }

  @override
  void addListener(VoidCallback listener) {
    if (_disposed) return;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_disposed) return;
    super.removeListener(listener);
  }

  Future<void> initRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  Future<List<Map<String, dynamic>>> _loadIce() async {
    final conf = await _calls.iceServers();
    final servers = conf["iceServers"];
    if (servers is List) {
      return servers.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [
      {"urls": "stun:stun.l.google.com:19302"},
    ];
  }

  Future<void> _ensurePeer(bool video) async {
    if (_disposed || _ending) return;
    await initRenderers();
    if (_disposed || _ending) return;

    final iceServers = await _loadIce();
    if (_disposed || _ending) return;
    _pc = await createPeerConnection({
      "iceServers": iceServers,
      "sdpSemantics": "unified-plan",
    });

    _pc!.onIceCandidate = (candidate) {
      if (_disposed || _ending) return;
      if (candidate.candidate == null || active == null) return;
      final payload = {
        "candidate": candidate.candidate,
        "sdpMid": candidate.sdpMid,
        "sdpMLineIndex": candidate.sdpMLineIndex,
      };
      _socket.sendCallSignal(
        type: "call.ice",
        organizationId: active!.organizationId,
        callId: active!.callId,
        toUserId: active!.peerUserId,
        fromUserId: localUserId,
        payload: payload,
      );
      unawaited(_postSignal("ice", payload));
    };

    _pc!.onTrack = (event) {
      if (_disposed || _ending) return;
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
        unawaited(_applyAudioRoute());
        _safeNotify();
      }
    };

    _pc!.onConnectionState = (state) {
      if (_disposed || _ending) return;
      if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        phase = CallPhase.active;
        _safeNotify();
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(endLocal(reason: "failed"));
      }
    };

    final mediaConstraints = <String, dynamic>{
      "audio": true,
      "video": video
          ? {
              "facingMode": "user",
              "width": 640,
              "height": 480,
            }
          : false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    if (_disposed || _ending) {
      try {
        await _localStream?.dispose();
      } catch (_) {}
      _localStream = null;
      return;
    }
    localRenderer.srcObject = _localStream;
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
    await _applyAudioRoute();
    _safeNotify();
  }

  double get _playbackVolume {
    if (speakerOn) return 1;
    if (kIsWeb) return 0.42;
    return 0.8;
  }

  Future<void> _applyAudioRoute() async {
    final volume = _playbackVolume;
    if (!kIsWeb) {
      try {
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          await Helper.setAppleAudioIOMode(
            AppleAudioIOMode.localAndRemote,
            preferSpeakerOutput: speakerOn,
          );
        }
        await Helper.setSpeakerphoneOn(speakerOn);
      } catch (e) {
        debugPrint("[call] speaker: $e");
      }
      final stream = remoteRenderer.srcObject;
      if (stream != null) {
        for (final track in stream.getAudioTracks()) {
          try {
            await Helper.setVolume(volume, track);
          } catch (_) {}
        }
      }
    }
    applyCallPlaybackVolume(volume);
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (!_disposed) applyCallPlaybackVolume(_playbackVolume);
    });
  }

  Future<void> startOutgoing({
    required String organizationId,
    required String calleeId,
    required String kind,
    String? conversationId,
    String? peerName,
    String? callerName,
  }) async {
    if (_disposed) return;
    error = null;
    phase = CallPhase.ringingOut;
    _safeNotify();

    try {
      final video = kind == "VIDEO";
      await _ensurePeer(video);
      if (_disposed || _ending || _pc == null) {
        await endLocal(reason: "media_unavailable");
        return;
      }

      final offer = await _pc!.createOffer({
        "offerToReceiveAudio": true,
        "offerToReceiveVideo": video,
      });
      await _pc!.setLocalDescription(offer);

      final created = await _calls.startCall(
        organizationId: organizationId,
        calleeId: calleeId,
        kind: kind,
        conversationId: conversationId,
        callerName: callerName,
        sdp: {"type": offer.type, "sdp": offer.sdp},
      );

      if (_disposed || _ending) return;

      active = ActiveCall(
        callId: created["callId"].toString(),
        organizationId: organizationId,
        peerUserId: calleeId,
        kind: kind,
        isCaller: true,
        peerName: peerName,
        conversationId: conversationId,
      );

      // Relaye l'offre via WS — fromUserId obligatoire pour que le pair
      // puisse répondre (sinon l'appel « sonne » chez l'appelant seulement).
      _lastOfferPayload = {
        "kind": kind,
        "sdp": {"type": offer.type, "sdp": offer.sdp},
        "callerName": callerName,
        if (conversationId != null) "conversationId": conversationId,
      };
      _socket.sendCallSignal(
        type: "call.offer",
        organizationId: organizationId,
        callId: active!.callId,
        toUserId: calleeId,
        fromUserId: localUserId,
        payload: _lastOfferPayload,
      );
      unawaited(_postSignal("offer", _lastOfferPayload!));
      _startOfferResend();
      _startRingTimeout();

      _safeNotify();
    } catch (e) {
      error = e.toString();
      await endLocal(reason: "start_failed");
      rethrow;
    }
  }

  void _startRingTimeout() {
    _ringTimeout?.cancel();
    _ringTimeout = Timer(const Duration(seconds: 45), () {
      if (_disposed || _ending) return;
      if (phase == CallPhase.ringingOut || phase == CallPhase.ringingIn) {
        debugPrint("[call] ring timeout");
        setStatusHint("Aucune réponse");
        unawaited(hangup());
      }
    });
  }

  void _stopRingTimeout() {
    _ringTimeout?.cancel();
    _ringTimeout = null;
  }

  void _startOfferResend() {
    _offerResendTimer?.cancel();
    var ticks = 0;
    _offerResendTimer = Timer.periodic(const Duration(seconds: 2), (t) {
      if (_disposed ||
          _ending ||
          phase != CallPhase.ringingOut ||
          active == null ||
          _lastOfferPayload == null) {
        t.cancel();
        return;
      }
      ticks++;
      if (ticks > 15) {
        t.cancel();
        return;
      }
      debugPrint("[call] resend offer tick=$ticks");
      _socket.sendCallSignal(
        type: "call.offer",
        organizationId: active!.organizationId,
        callId: active!.callId,
        toUserId: active!.peerUserId,
        fromUserId: localUserId,
        payload: _lastOfferPayload,
      );
    });
  }

  void _stopOfferResend() {
    _offerResendTimer?.cancel();
    _offerResendTimer = null;
    _lastOfferPayload = null;
  }

  /// Appel entrant reçu via WS `call.offer` ou via le sondage REST.
  Future<void> handleIncomingOffer(Map<String, dynamic> event) async {
    final payload = event["payload"];
    final p = payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{};
    final fromId = event["fromUserId"]?.toString() ??
        event["callerId"]?.toString() ??
        p["fromUserId"]?.toString() ??
        p["callerId"]?.toString();
    if (fromId == null || fromId.isEmpty || fromId == localUserId) {
      debugPrint("[call] ignore offer — missing/own fromUserId");
      return;
    }
    final callId = event["callId"]?.toString() ?? "";
    if (callId.isEmpty) return;
    final sdp = _sdpMap(p["sdp"]);
    if (active?.callId == callId && phase == CallPhase.ringingIn) {
      if (_incomingSdp == null && sdp != null) _incomingSdp = sdp;
      return;
    }
    if (phase != CallPhase.idle) return;
    active = ActiveCall(
      callId: callId,
      organizationId: event["organizationId"].toString(),
      peerUserId: fromId,
      kind: (p["kind"] ?? event["kind"] ?? "AUDIO").toString(),
      isCaller: false,
      peerName: p["callerName"]?.toString() ?? event["callerName"]?.toString(),
      conversationId: p["conversationId"]?.toString() ??
          event["conversationId"]?.toString(),
    );
    phase = CallPhase.ringingIn;
    _incomingSdp = sdp;
    _answerApplied = false;
    _startRingTimeout();
    _safeNotify();
    debugPrint("[call] incoming $callId from $fromId");
    onIncomingRing?.call(active!);
  }

  Map<String, dynamic>? _sdpFromSignal(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final nested = map["sdp"];
    if (nested is Map) return _sdpMap(nested);
    return _sdpMap(map);
  }

  Map<String, dynamic>? _sdpMap(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final sdp = map["sdp"]?.toString();
    if (sdp == null || sdp.isEmpty) return null;
    return map;
  }

  Future<void> _postSignal(String type, Map<String, dynamic> payload) async {
    final call = active;
    if (call == null || _disposed) return;
    try {
      await _calls.postSignal(
        organizationId: call.organizationId,
        callId: call.callId,
        type: type,
        payload: payload,
      );
    } catch (e) {
      debugPrint("[call] post signal $type failed: $e");
    }
  }

  /// Sonnerie entrante via HTTP si le websocket n'a pas livré l'offre.
  Future<void> pollIncoming(List<String> organizationIds) async {
    if (_disposed || _ending || phase != CallPhase.idle) return;
    try {
      final data = await _calls.incoming();
      final items = (data["items"] as List?) ?? const [];
      for (final raw in items) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        await handleIncomingOffer({
          "callId": item["callId"],
          "organizationId": item["organizationId"],
          "fromUserId": item["callerId"],
          "toUserId": localUserId,
          "callerName": item["callerName"],
          "kind": item["kind"],
          "conversationId": item["conversationId"],
          "payload": {
            "kind": item["kind"],
            "sdp": item["sdp"],
            "callerName": item["callerName"],
            "conversationId": item["conversationId"],
          },
        });
        return;
      }
      return;
    } catch (e) {
      debugPrint("[call] /calls/incoming: $e");
    }

    final cutoff = DateTime.now().toUtc().subtract(const Duration(seconds: 50));
    for (final orgId in organizationIds) {
      if (phase != CallPhase.idle) return;
      try {
        final data = await _calls.history(orgId);
        final items = (data["items"] as List?) ?? const [];
        for (final raw in items) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          if (item["status"]?.toString() != "RINGING") continue;
          if (item["calleeId"]?.toString() != localUserId) continue;
          final started = DateTime.tryParse(item["startedAt"]?.toString() ?? "");
          if (started != null && started.toUtc().isBefore(cutoff)) continue;
          final callId = item["id"]?.toString();
          if (callId == null || callId.isEmpty) continue;
          dynamic sdp;
          try {
            final signal = await _calls.callSignal(
              organizationId: orgId,
              callId: callId,
            );
            sdp = signal["offer"] is Map
                ? (signal["offer"] as Map)["sdp"]
                : null;
          } catch (_) {}
          await handleIncomingOffer({
            "callId": callId,
            "organizationId": orgId,
            "fromUserId": item["callerId"],
            "toUserId": localUserId,
            "kind": item["kind"],
            "conversationId": item["conversationId"],
            "payload": {
              "kind": item["kind"],
              "sdp": sdp,
              "conversationId": item["conversationId"],
            },
          });
          return;
        }
      } catch (e) {
        debugPrint("[call] history poll $orgId: $e");
      }
    }
  }

  /// Récupère réponse / ICE / fin d'appel quand le websocket n'a pas livré.
  Future<void> pullRemoteSignal() async {
    final call = active;
    if (call == null || _disposed || _ending) return;
    Map<String, dynamic> data;
    try {
      data = await _calls.callSignal(
        organizationId: call.organizationId,
        callId: call.callId,
      );
    } catch (e) {
      debugPrint("[call] pull signal failed: $e");
      return;
    }
    if (_disposed || _ending || active?.callId != call.callId) return;

    final status = data["status"]?.toString() ?? "";
    if (status == "REJECTED" || status == "ENDED" || status == "MISSED") {
      if (phase == CallPhase.ringingIn ||
          phase == CallPhase.ringingOut ||
          phase == CallPhase.connecting) {
        await endLocal(reason: status);
      }
      return;
    }

    if (call.isCaller && !_answerApplied) {
      final answer = data["answer"];
      final sdp = _sdpFromSignal(answer);
      if (sdp != null && _pc != null) {
        _answerApplied = true;
        await _pc!.setRemoteDescription(
          RTCSessionDescription(
            sdp["sdp"] as String,
            sdp["type"] as String? ?? "answer",
          ),
        );
        await _flushPendingIce();
        phase = CallPhase.active;
        _stopOfferResend();
        _stopRingTimeout();
        _safeNotify();
      }
    } else if (!call.isCaller && _incomingSdp == null) {
      _incomingSdp = _sdpFromSignal(data["offer"]);
    }

    final ice = data["ice"];
    if (ice is List) {
      for (final raw in ice) {
        if (raw is! Map) continue;
        await _addRemoteIce(Map<String, dynamic>.from(raw));
      }
    }
  }

  Future<void> _addRemoteIce(Map<String, dynamic> p) async {
    final value = p["candidate"]?.toString();
    if (value == null || value.isEmpty) return;
    if (!_appliedRemoteIce.add(value)) return;
    final index = p["sdpMLineIndex"];
    final candidate = RTCIceCandidate(
      value,
      p["sdpMid"] as String?,
      index is int ? index : (index is num ? index.toInt() : null),
    );
    if (_pc == null) {
      _pendingRemoteIce.add(candidate);
      return;
    }
    try {
      await _pc!.addCandidate(candidate);
    } catch (e) {
      debugPrint("ICE add failed $e");
    }
  }

  Map<String, dynamic>? _incomingSdp;

  Future<void> acceptIncoming() async {
    if (active == null || phase != CallPhase.ringingIn) return;
    error = null;
    phase = CallPhase.connecting;
    _safeNotify();

    final video = active!.kind == "VIDEO";
    await _ensurePeer(video);
    if (_incomingSdp == null) {
      await pullRemoteSignal();
    }
    if (_pc == null || _disposed || _ending) return;
    if (_incomingSdp == null || _incomingSdp!["sdp"] == null) {
      error = "Offre d'appel introuvable";
      await endLocal(reason: "missing_offer");
      return;
    }

    await _pc!.setRemoteDescription(
      RTCSessionDescription(
        _incomingSdp!["sdp"] as String,
        _incomingSdp!["type"] as String? ?? "offer",
      ),
    );
    await _flushPendingIce();

    final answer = await _pc!.createAnswer({
      "offerToReceiveAudio": true,
      "offerToReceiveVideo": video,
    });
    await _pc!.setLocalDescription(answer);

    final answerSdp = {"type": answer.type, "sdp": answer.sdp};
    await _postSignal("answer", {"sdp": answerSdp});
    await _calls.callAction(
      organizationId: active!.organizationId,
      callId: active!.callId,
      action: "answer",
      sdp: answerSdp,
    );

    _socket.sendCallSignal(
      type: "call.answer",
      organizationId: active!.organizationId,
      callId: active!.callId,
      toUserId: active!.peerUserId,
      fromUserId: localUserId,
      payload: {"sdp": answerSdp},
    );

    phase = CallPhase.active;
    _stopOfferResend();
    _stopRingTimeout();
    _safeNotify();
  }

  Future<void> rejectIncoming() async {
    final call = active;
    if (call == null || _ending || _disposed) return;
    try {
      await _calls.callAction(
        organizationId: call.organizationId,
        callId: call.callId,
        action: "reject",
      );
    } catch (_) {}
    try {
      _socket.sendCallSignal(
        type: "call.reject",
        organizationId: call.organizationId,
        callId: call.callId,
        toUserId: call.peerUserId,
        fromUserId: localUserId,
      );
    } catch (_) {}
    await endLocal(reason: "rejected");
  }

  Future<void> hangup() async {
    final call = active;
    if (call == null || _ending || _disposed) return;
    try {
      await _calls.callAction(
        organizationId: call.organizationId,
        callId: call.callId,
        action: "hangup",
      );
    } catch (_) {}
    try {
      _socket.sendCallSignal(
        type: "call.hangup",
        organizationId: call.organizationId,
        callId: call.callId,
        toUserId: call.peerUserId,
        fromUserId: localUserId,
      );
    } catch (_) {}
    await endLocal(reason: "hangup");
  }

  Future<void> endLocal({String? reason}) async {
    if (_ending || _disposed) return;
    if (phase == CallPhase.idle && active == null) return;
    _stopOfferResend();
    _stopRingTimeout();
    _ending = true;
    try {
      phase = CallPhase.ended;
      _safeNotify();
      await _cleanup();
      if (_disposed) return;
      phase = CallPhase.idle;
      active = null;
      error = reason;
      _safeNotify();
    } finally {
      _ending = false;
    }
  }

  Future<void> toggleSpeaker() async {
    if (_disposed || _ending) return;
    speakerOn = !speakerOn;
    try {
      await _applyAudioRoute();
    } catch (_) {}
    _safeNotify();
  }

  Future<void> toggleMute() async {
    if (_disposed || _ending) return;
    micMuted = !micMuted;
    try {
      _localStream?.getAudioTracks().forEach((t) {
        t.enabled = !micMuted;
      });
    } catch (_) {}
    _safeNotify();
  }

  Future<void> toggleCamera() async {
    if (_disposed || _ending) return;
    if (active?.kind != "VIDEO") return;
    camOff = !camOff;
    try {
      _localStream?.getVideoTracks().forEach((t) {
        t.enabled = !camOff;
      });
    } catch (_) {}
    _safeNotify();
  }

  Future<void> _onSignal(Map<String, dynamic> event) async {
    if (_disposed || _ending) return;
    final type = event["type"]?.toString() ?? "";
    final callId = event["callId"]?.toString();

    if (type == "call.offer" && event["toUserId"]?.toString() == localUserId) {
      if (event["fromUserId"]?.toString() == localUserId) return;
      await handleIncomingOffer(event);
      return;
    }

    if (active == null || callId != active!.callId) {
      // Incoming offer already handled; ignore other calls while busy
      return;
    }

    final payload = event["payload"];
    final p = payload is Map ? Map<String, dynamic>.from(payload) : null;

    switch (type) {
      case "call.answer":
        if (active!.isCaller && !_answerApplied && p?["sdp"] is Map) {
          final sdp = Map<String, dynamic>.from(p!["sdp"] as Map);
          _answerApplied = true;
          await _pc?.setRemoteDescription(
            RTCSessionDescription(
              sdp["sdp"] as String,
              sdp["type"] as String? ?? "answer",
            ),
          );
          await _flushPendingIce();
          phase = CallPhase.active;
          _stopOfferResend();
          _stopRingTimeout();
          try {
            await _calls.callAction(
              organizationId: active!.organizationId,
              callId: active!.callId,
              action: "answer",
            );
          } catch (_) {}
          _safeNotify();
        }
        break;
      case "call.ice":
        if (p == null) return;
        await _addRemoteIce(p);
        break;
      case "call.reject":
      case "call.hangup":
        await endLocal(reason: type);
        break;
    }
  }

  Future<void> _flushPendingIce() async {
    if (_pc == null) return;
    for (final c in _pendingRemoteIce) {
      try {
        await _pc!.addCandidate(c);
      } catch (_) {}
    }
    _pendingRemoteIce.clear();
  }

  void _safeNotify() {
    if (_disposed) return;
    try {
      notifyListeners();
    } catch (_) {}
  }

  /// Arrêt media sans planter si la vue vidéo est encore montée.
  Future<void> _cleanup() async {
    try {
      localRenderer.srcObject = null;
    } catch (_) {}
    try {
      remoteRenderer.srcObject = null;
    } catch (_) {}

    // Laisse RTCVideoView détacher le flux avant dispose natif.
    await Future<void>.delayed(const Duration(milliseconds: 80));

    try {
      final tracks = _localStream?.getTracks() ?? const <MediaStreamTrack>[];
      for (final t in tracks) {
        try {
          await t.stop();
        } catch (_) {}
      }
    } catch (_) {}

    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;

    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    _pendingRemoteIce.clear();
    _appliedRemoteIce.clear();
    _answerApplied = false;
    _incomingSdp = null;
    speakerOn = false;
  }

  /// Teardown synchrone best-effort (swipe kill / dispose Riverpod).
  void forceTeardown() {
    _stopOfferResend();
    _stopRingTimeout();
    _ending = true;
    try {
      localRenderer.srcObject = null;
    } catch (_) {}
    try {
      remoteRenderer.srcObject = null;
    } catch (_) {}
    try {
      _localStream?.getTracks().forEach((t) {
        try {
          t.stop();
        } catch (_) {}
      });
    } catch (_) {}
    try {
      _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    try {
      _pc?.close();
    } catch (_) {}
    _pc = null;
    phase = CallPhase.idle;
    active = null;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _socket.onCallEvent = null;
    onIncomingRing = null;
    forceTeardown();
    try {
      if (_renderersReady) {
        localRenderer.dispose();
        remoteRenderer.dispose();
      }
    } catch (_) {}
    _renderersReady = false;
    super.dispose();
  }
}
