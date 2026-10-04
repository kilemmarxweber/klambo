import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:klambo_messagerie/data/calls_repository.dart";
import "package:klambo_messagerie/data/messaging_socket.dart";
import "package:klambo_messagerie/features/calls/call_identity.dart";
import "package:klambo_messagerie/features/calls/call_link.dart";
import "package:klambo_messagerie/features/calls/call_media_stats.dart";
import "package:klambo_messagerie/features/calls/call_signal_policy.dart";
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
    CallIdentity? identity,
  })  : _calls = calls,
        _socket = socket,
        _identity = identity {
    _socket.onCallEvent = _onSignal;
  }

  final CallsRepository _calls;
  final MessagingSocket _socket;
  final CallIdentity? _identity;
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
  /// host, srflx, relay ou unknown — renseigné pendant l'appel.
  String icePath = "unknown";
  final List<RTCIceCandidate> _pendingRemoteIce = [];
  final Set<String> _appliedRemoteIce = {};
  bool _answerApplied = false;
  Timer? _offerResendTimer;
  DateTime? _historyFallbackAt;
  Timer? _ringTimeout;
  Timer? _restartTimer;
  Timer? _giveUpTimer;
  Timer? _connectBudget;
  Map<String, dynamic>? _lastOfferPayload;
  final CallLink _link = CallLink();
  bool _restartRequestSent = false;
  bool _offerAcked = false;
  Timer? _statsTimer;
  int _videoBitrate = videoBitrateSteps.last;
  int _prevLost = 0;
  int _prevReceived = 0;

  bool get peerIsRinging => _offerAcked;

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
      if (persistIceOnRest(socketConnected: _socket.isConnected)) {
        unawaited(_postSignal("ice", payload));
      }
    };

    _pc!.onTrack = (event) {
      if (_disposed || _ending) return;
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
        unawaited(_applyAudioRoute());
        _safeNotify();
      }
    };

    // ICE connection state drives media-up / restart / fail (CallLink).
    // PeerConnection state is a separate aggregate — do not feed it through
    // parseIceSignal / _onLinkSignal (duplicate transitions + wrong restarts).
    _pc!.onIceConnectionState = (state) {
      if (_disposed || _ending) return;
      _onLinkSignal(parseIceSignal(state.toString()));
    };

    _pc!.onConnectionState = (state) {
      if (_disposed || _ending) return;
      debugPrint("[call] pc connectionState=$state");
    };

    final mediaConstraints = <String, dynamic>{
      "audio": {
        "echoCancellation": true,
        "noiseSuppression": true,
        "autoGainControl": true,
      },
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

  bool get _mediaPhase =>
      phase == CallPhase.connecting || phase == CallPhase.active;

  void onNetworkChanged() {
    if (_disposed || _ending) return;
    final action = _link.onNetworkChanged(mediaPhase: _mediaPhase);
    if (action == CallLinkAction.scheduleRestart) {
      _armRestart(const Duration(milliseconds: 600));
    }
  }

  void _onLinkSignal(CallIceSignal signal) {
    if (!_mediaPhase && signal != CallIceSignal.connected &&
        signal != CallIceSignal.completed) {
      return;
    }
    final action = _link.onIce(signal);
    switch (action) {
      case CallLinkAction.mediaUp:
        _restartTimer?.cancel();
        _restartTimer = null;
        _giveUpTimer?.cancel();
        _giveUpTimer = null;
        _stopConnectBudget();
        _restartRequestSent = false;
        if (phase != CallPhase.active) {
          phase = CallPhase.active;
          _stopRingTimeout();
          _safeNotify();
        }
        _ensureStats();
        break;
      case CallLinkAction.scheduleRestart:
        _armRestart(CallLink.disconnectGrace);
        break;
      case CallLinkAction.restartNow:
        _armRestart(Duration.zero);
        break;
      case CallLinkAction.endFailed:
        unawaited(endLocal(reason: "failed", notifyPeer: true));
        break;
      case CallLinkAction.none:
        break;
    }
  }

  void _armRestart(Duration delay) {
    if (_restartTimer != null || _disposed || _ending) return;
    _restartTimer = Timer(delay, () {
      _restartTimer = null;
      unawaited(_performRestart());
    });
  }

  Future<void> _performRestart() async {
    if (_disposed || _ending || active == null || !_mediaPhase) {
      _link.disarm();
      return;
    }
    if (!active!.isCaller) {
      _link.disarm();
      _requestPeerRestart();
      _armGiveUp();
      return;
    }
    final action = _link.takeRestart();
    if (action == CallLinkAction.endFailed) {
      await endLocal(reason: "failed", notifyPeer: true);
      return;
    }
    if (action != CallLinkAction.restartNow) return;
    await _sendIceRestart();
  }

  void _requestPeerRestart() {
    final call = active;
    if (call == null || _restartRequestSent) return;
    _restartRequestSent = true;
    _socket.sendCallSignal(
      type: "call.restart-request",
      organizationId: call.organizationId,
      callId: call.callId,
      toUserId: call.peerUserId,
      fromUserId: localUserId,
    );
  }

  void _armGiveUp() {
    if (_giveUpTimer != null) return;
    _giveUpTimer = Timer(const Duration(seconds: 12), () {
      _giveUpTimer = null;
      if (_disposed || _ending || _link.mediaUp) return;
      unawaited(endLocal(reason: "failed", notifyPeer: true));
    });
  }

  Future<void> _sendIceRestart() async {
    final call = active;
    final pc = _pc;
    if (call == null || pc == null || _disposed || _ending) {
      _link.disarm();
      return;
    }
    try {
      try {
        await pc.restartIce();
      } catch (e) {
        debugPrint("[call] restartIce: $e");
      }
      final video = call.kind == "VIDEO";
      final offer = await pc.createOffer({
        "iceRestart": true,
        "offerToReceiveAudio": true,
        "offerToReceiveVideo": video,
      });
      await pc.setLocalDescription(offer);
      final offerSdp = await _describedSdp(offer);
      final payload = await _seal({
        "iceRestart": true,
        "sdp": offerSdp,
      });
      _socket.sendCallSignal(
        type: "call.renegotiate",
        organizationId: call.organizationId,
        callId: call.callId,
        toUserId: call.peerUserId,
        fromUserId: localUserId,
        payload: payload,
      );
      debugPrint("[call] ice restart offer sent");
    } catch (e) {
      debugPrint("[call] ice restart failed: $e");
      _link.disarm();
      await endLocal(reason: "failed", notifyPeer: true);
    }
  }

  Future<void> _acceptRenegotiation(Map<String, dynamic> p) async {
    final call = active;
    final pc = _pc;
    if (call == null || pc == null || call.isCaller) return;
    final sdp = _sdpMap(p["sdp"]);
    if (sdp == null) return;
    if (!await _guard(call.peerUserId, p)) return;
    final video = call.kind == "VIDEO";
    await pc.setRemoteDescription(
      RTCSessionDescription(
        sdp["sdp"] as String,
        sdp["type"] as String? ?? "offer",
      ),
    );
    await _flushPendingIce();
    final answer = await pc.createAnswer({
      "offerToReceiveAudio": true,
      "offerToReceiveVideo": video,
    });
    await pc.setLocalDescription(answer);
    final answerSdp = await _describedSdp(answer);
    final payload = await _seal({
      "sdp": answerSdp,
      "iceRestart": true,
    });
    final dtls = payload["dtls"] is Map
        ? Map<String, dynamic>.from(payload["dtls"] as Map)
        : null;
    _socket.sendCallSignal(
      type: "call.answer",
      organizationId: call.organizationId,
      callId: call.callId,
      toUserId: call.peerUserId,
      fromUserId: localUserId,
      payload: payload,
    );
    // Persist like acceptIncoming so a lost WS answer still reaches the peer.
    await _calls.callAction(
      organizationId: call.organizationId,
      callId: call.callId,
      action: "answer",
      sdp: answerSdp,
      dtls: dtls,
    );
    if (!_socket.isConnected) {
      await _postSignal("answer", {
        "sdp": answerSdp,
        "iceRestart": true,
      });
    }
  }

  void _cancelLinkTimers() {
    _restartTimer?.cancel();
    _restartTimer = null;
    _giveUpTimer?.cancel();
    _giveUpTimer = null;
    _stopConnectBudget();
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  /// Temps pour établir l'audio après le décroché, sans couper pendant la collecte ICE.
  void _armConnectBudget() {
    if (_link.mediaUp || _connectBudget != null || _disposed || _ending) return;
    _connectBudget = Timer(CallLink.initialConnectBudget, () {
      _connectBudget = null;
      if (_disposed || _ending || _link.mediaUp) return;
      if (phase != CallPhase.connecting) return;
      unawaited(endLocal(reason: "failed", notifyPeer: true));
    });
  }

  void _stopConnectBudget() {
    _connectBudget?.cancel();
    _connectBudget = null;
  }

  /// SDP réellement posé (empreinte DTLS comprise), pas le brouillon de createOffer.
  Future<Map<String, dynamic>> _describedSdp(
    RTCSessionDescription created,
  ) async {
    RTCSessionDescription? local;
    try {
      local = await _pc?.getLocalDescription();
    } catch (e) {
      debugPrint("[call] getLocalDescription: $e");
    }
    final sdp = (local?.sdp != null && local!.sdp!.isNotEmpty)
        ? local.sdp
        : created.sdp;
    final type = (local?.type != null && local!.type!.isNotEmpty)
        ? local.type
        : created.type;
    return {"type": type, "sdp": sdp};
  }

  void _ensureStats() {
    if (_statsTimer != null || _disposed) return;
    _statsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_sampleStats());
    });
  }

  Future<void> _sampleStats() async {
    final pc = _pc;
    if (pc == null || _disposed || _ending) return;
    try {
      final reports = await pc.getStats();
      final snap = parseCallStats([
        for (final report in reports)
          {
            "id": report.id,
            "type": report.type,
            "values": Map<String, dynamic>.from(report.values),
          },
      ]);
      if (snap.path != icePath) {
        icePath = snap.path;
        debugPrint("[call] ice path $icePath");
        _safeNotify();
      }
      if (active?.kind != "VIDEO") return;
      final deltaLost = snap.packetsLost - _prevLost;
      final deltaReceived = snap.packetsReceived - _prevReceived;
      _prevLost = snap.packetsLost;
      _prevReceived = snap.packetsReceived;
      if (deltaLost < 0 || deltaReceived < 0) return;
      final next = nextVideoBitrate(
        current: _videoBitrate,
        deltaLost: deltaLost,
        deltaReceived: deltaReceived,
        rttMs: snap.rttMs,
      );
      if (next == _videoBitrate) return;
      _videoBitrate = next;
      await _applyVideoBitrate(next);
      debugPrint("[call] video bitrate $next");
    } catch (e) {
      debugPrint("[call] stats: $e");
    }
  }

  Future<void> _applyVideoBitrate(int bitrate) async {
    final pc = _pc;
    if (pc == null) return;
    final senders = await pc.getSenders();
    for (final sender in senders) {
      if (sender.track?.kind != "video") continue;
      final params = sender.parameters;
      final encodings = params.encodings;
      if (encodings == null || encodings.isEmpty) continue;
      encodings.first.maxBitrate = bitrate;
      await sender.setParameters(params);
    }
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
      await _identity?.ensureRegistered();
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

      final offerSdp = await _describedSdp(offer);
      final sealedOffer = await _seal({"sdp": offerSdp});
      final created = await _calls.startCall(
        organizationId: organizationId,
        calleeId: calleeId,
        kind: kind,
        conversationId: conversationId,
        callerName: callerName,
        sdp: offerSdp,
        dtls: sealedOffer["dtls"] is Map
            ? Map<String, dynamic>.from(sealedOffer["dtls"] as Map)
            : null,
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
        "sdp": offerSdp,
        "callerName": callerName,
        if (sealedOffer["dtls"] != null) "dtls": sealedOffer["dtls"],
        if (conversationId != null) "conversationId": conversationId,
      };
      _offerAcked = false;
      _socket.sendCallSignal(
        type: "call.offer",
        organizationId: organizationId,
        callId: active!.callId,
        toUserId: calleeId,
        fromUserId: localUserId,
        payload: _lastOfferPayload,
      );
      if (persistOfferSnapshotOnRest(socketConnected: _socket.isConnected)) {
        unawaited(_postSignal("offer", _lastOfferPayload!));
      }
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
          !shouldResendOffer(
            acked: _offerAcked,
            ringingOut: phase == CallPhase.ringingOut,
          ) ||
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
    _offerAcked = false;
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
    final inCall = phase != CallPhase.idle && phase != CallPhase.ended;
    if (shouldReplyBusy(inCall: inCall, sameCall: active?.callId == callId)) {
      final org = event["organizationId"]?.toString() ?? "";
      if (org.isNotEmpty) {
        _socket.sendCallSignal(
          type: "call.busy",
          organizationId: org,
          callId: callId,
          toUserId: fromId,
          fromUserId: localUserId,
        );
      }
      debugPrint("[call] busy — ignored $callId");
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
    _incomingDtls = p["dtls"];
    _answerApplied = false;
    _socket.sendCallSignal(
      type: "call.ack",
      organizationId: active!.organizationId,
      callId: callId,
      toUserId: fromId,
      fromUserId: localUserId,
    );
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
            "dtls": item["dtls"],
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

    final now = DateTime.now();
    if (_historyFallbackAt != null &&
        now.difference(_historyFallbackAt!) < const Duration(seconds: 60)) {
      return;
    }
    _historyFallbackAt = now;

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
          dynamic dtls;
          try {
            final signal = await _calls.callSignal(
              organizationId: orgId,
              callId: callId,
            );
            final offer = signal["offer"];
            if (offer is Map) {
              sdp = offer["sdp"];
              dtls = offer["dtls"];
            }
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
              "dtls": dtls,
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
        final endReason = data["endReason"]?.toString();
        await endLocal(reason: endReason == "busy" ? "busy" : status);
      }
      return;
    }

    if (call.isCaller && !_answerApplied) {
      final answer = data["answer"];
      final sdp = _sdpFromSignal(answer);
      if (sdp != null && _pc != null) {
        final container = answer is Map
            ? Map<String, dynamic>.from(answer)
            : <String, dynamic>{"sdp": sdp};
        if (!await _guard(call.peerUserId, container)) return;
        if (phase == CallPhase.ringingOut) {
          phase = CallPhase.connecting;
          _armConnectBudget();
        }
        await _pc!.setRemoteDescription(
          RTCSessionDescription(
            sdp["sdp"] as String,
            sdp["type"] as String? ?? "answer",
          ),
        );
        await _flushPendingIce();
        _answerApplied = true;
        if (markActiveOnAnswer(mediaAlreadyUp: _link.mediaUp)) {
          phase = CallPhase.active;
        } else {
          phase = CallPhase.connecting;
          _armConnectBudget();
        }
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
  dynamic _incomingDtls;

  Future<Map<String, dynamic>> _seal(Map<String, dynamic> payload) async {
    final identity = _identity;
    if (identity == null) return payload;
    final sdp = _sdpMap(payload["sdp"]);
    final text = sdp?["sdp"]?.toString();
    if (text == null || text.isEmpty) return payload;
    final dtls = await identity.proofFor(text);
    return {...payload, "dtls": dtls};
  }

  Future<bool> _guard(String peerId, Map<String, dynamic>? container) async {
    final identity = _identity;
    if (identity == null || container == null) return true;
    final sdp = _sdpMap(container["sdp"]) ?? _sdpFromSignal(container);
    final text = sdp?["sdp"]?.toString() ?? "";
    try {
      await identity.verify(
        peerUserId: peerId,
        sdp: text,
        dtls: container["dtls"],
      );
      return true;
    } on CallIdentityException {
      await endLocal(reason: "identity", notifyPeer: true);
      return false;
    }
  }

  Future<void> acceptIncoming() async {
    if (active == null || phase != CallPhase.ringingIn) return;
    error = null;
    phase = CallPhase.connecting;
    _armConnectBudget();
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
    if (!await _guard(active!.peerUserId, {
      "sdp": _incomingSdp,
      "dtls": _incomingDtls,
    })) {
      return;
    }
    await _identity?.ensureRegistered();

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

    final answerSdp = await _describedSdp(answer);
    final sealedAnswer = await _seal({"sdp": answerSdp});
    final dtls = sealedAnswer["dtls"] is Map
        ? Map<String, dynamic>.from(sealedAnswer["dtls"] as Map)
        : null;
    _socket.sendCallSignal(
      type: "call.answer",
      organizationId: active!.organizationId,
      callId: active!.callId,
      toUserId: active!.peerUserId,
      fromUserId: localUserId,
      payload: sealedAnswer,
    );
    await _calls.callAction(
      organizationId: active!.organizationId,
      callId: active!.callId,
      action: "answer",
      sdp: answerSdp,
      dtls: dtls,
    );
    if (!_socket.isConnected) {
      await _postSignal("answer", {"sdp": answerSdp});
    }

    phase = markActiveOnAnswer(mediaAlreadyUp: _link.mediaUp)
        ? CallPhase.active
        : CallPhase.connecting;
    if (phase == CallPhase.connecting) _armConnectBudget();
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

  Future<void> endLocal({String? reason, bool notifyPeer = false}) async {
    if (_ending || _disposed) return;
    if (phase == CallPhase.idle && active == null) return;
    final call = active;
    _stopOfferResend();
    _stopRingTimeout();
    _cancelLinkTimers();
    _ending = true;
    if (notifyPeer && call != null) {
      try {
        _socket.sendCallSignal(
          type: "call.hangup",
          organizationId: call.organizationId,
          callId: call.callId,
          toUserId: call.peerUserId,
          fromUserId: localUserId,
        );
      } catch (_) {}
      try {
        await _calls.callAction(
          organizationId: call.organizationId,
          callId: call.callId,
          action: "hangup",
          endReason: reason,
        );
      } catch (_) {}
    }
    try {
      phase = CallPhase.ended;
      _safeNotify();
      await _cleanup();
      if (_disposed) return;
      if (reason == "busy" || reason == "failed" || reason == "identity") {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (_disposed) return;
      }
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
        final restart = p?["iceRestart"] == true;
        if (active!.isCaller && p?["sdp"] is Map && (restart || !_answerApplied)) {
          final sdp = Map<String, dynamic>.from(p!["sdp"] as Map);
          if (!await _guard(active!.peerUserId, p)) return;
          try {
            if (phase == CallPhase.ringingOut) {
              phase = CallPhase.connecting;
              _armConnectBudget();
            }
            await _pc?.setRemoteDescription(
              RTCSessionDescription(
                sdp["sdp"] as String,
                sdp["type"] as String? ?? "answer",
              ),
            );
            if (!restart) _answerApplied = true;
            await _flushPendingIce();
            phase = markActiveOnAnswer(mediaAlreadyUp: _link.mediaUp)
                ? CallPhase.active
                : CallPhase.connecting;
            if (phase == CallPhase.connecting) _armConnectBudget();
            _stopOfferResend();
            _stopRingTimeout();
            _safeNotify();
          } catch (e) {
            debugPrint("[call] answer apply failed: $e");
          }
        }
        break;
      case "call.renegotiate":
        if (p != null) {
          try {
            await _acceptRenegotiation(p);
          } catch (e) {
            debugPrint("[call] renegotiate failed: $e");
          }
        }
        break;
      case "call.restart-request":
        if (active!.isCaller) {
          _link.disarm();
          _armRestart(Duration.zero);
        }
        break;
      case "call.ack":
        if (active!.isCaller && phase == CallPhase.ringingOut) {
          _offerAcked = true;
          _offerResendTimer?.cancel();
          _offerResendTimer = null;
          debugPrint("[call] offer acked");
          _safeNotify();
        }
        break;
      case "call.busy":
        if (active!.isCaller &&
            (phase == CallPhase.ringingOut || phase == CallPhase.connecting)) {
          await endLocal(reason: "busy");
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
    _incomingDtls = null;
    speakerOn = false;
    _restartRequestSent = false;
    _offerAcked = false;
    icePath = "unknown";
    _videoBitrate = videoBitrateSteps.last;
    _prevLost = 0;
    _prevReceived = 0;
    _link.reset();
  }

  /// Teardown synchrone best-effort (swipe kill / dispose Riverpod).
  void forceTeardown() {
    _stopOfferResend();
    _stopRingTimeout();
    _cancelLinkTimers();
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
    _link.reset();
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
