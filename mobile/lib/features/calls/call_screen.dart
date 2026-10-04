import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:klambo_messagerie/core/l10n.dart";
import "package:klambo_messagerie/features/calls/call_controller.dart";

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key, required this.controller});

  final CallController controller;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  late final CallController _c;
  bool _actionBusy = false;
  bool _popScheduled = false;
  DateTime? _connectedAt;
  Duration _elapsed = Duration.zero;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _c = widget.controller;
    _c.addListener(_onUpdate);
    if (_c.phase == CallPhase.active) _startClock();
  }

  void _startClock() {
    _connectedAt ??= DateTime.now();
    _elapsed = DateTime.now().difference(_connectedAt!);
    _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _connectedAt == null) return;
      setState(() {
        _elapsed = DateTime.now().difference(_connectedAt!);
      });
    });
  }

  void _stopClock() {
    _clock?.cancel();
    _clock = null;
  }

  String get _clockLabel {
    final total = _elapsed.inSeconds;
    final h = total ~/ 3600;
    final m = (total ~/ 60) % 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, "0");
    final ss = s.toString().padLeft(2, "0");
    if (h > 0) return "$h:$mm:$ss";
    return "$mm:$ss";
  }

  void _onUpdate() {
    if (!mounted || _c.isDisposed) return;
    if (_c.phase == CallPhase.active) {
      _startClock();
    } else if (_c.phase == CallPhase.idle || _c.phase == CallPhase.ended) {
      _stopClock();
    }
    if (_c.phase == CallPhase.idle) {
      _schedulePop();
      return;
    }
    setState(() {});
  }

  void _minimize() {
    if (!_c.isBusy) return;
    _c.setMinimized(true);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _schedulePop() {
    if (_popScheduled || !mounted) return;
    _popScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).maybePop();
    });
  }

  Future<void> _safeAction(Future<void> Function() action) async {
    if (_actionBusy || _c.isDisposed) return;
    setState(() => _actionBusy = true);
    try {
      await action();
    } catch (e) {
      debugPrint("[call] action failed: $e");
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  void dispose() {
    _stopClock();
    if (!_c.isDisposed) {
      _c.removeListener(_onUpdate);
    }
    super.dispose();
  }

  String _statusLabel(L10n l10n, {required bool peerReachable}) {
    final hint = _c.error?.trim();
    if (hint != null &&
        hint.isNotEmpty &&
        (_c.phase == CallPhase.ringingOut ||
            _c.phase == CallPhase.ended ||
            _c.phase == CallPhase.idle)) {
      if (hint == "busy") return l10n.callBusy;
      if (hint == "failed") return l10n.callMediaLost;
      if (hint == "identity") return l10n.callIdentityFailed;
      return hint;
    }
    switch (_c.phase) {
      case CallPhase.ringingOut:
        return peerReachable ? l10n.callRingingOut : l10n.callPeerAway;
      case CallPhase.ringingIn:
        return l10n.callRingingIn;
      case CallPhase.connecting:
        return l10n.callConnecting;
      case CallPhase.active:
        return _c.active?.kind == "VIDEO"
            ? l10n.callVideoActive
            : l10n.callAudioActive;
      case CallPhase.ended:
        return l10n.callEnded;
      case CallPhase.idle:
        return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final peerReachable = _c.peerIsRinging;
    if (_c.isDisposed) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B1F17),
        body: SizedBox.shrink(),
      );
    }
    final isVideo = _c.active?.kind == "VIDEO";
    final name = _c.active?.peerName ?? l10n.callPeerFallback;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _minimize();
          return;
        }
        if (_c.isBusy) _c.setMinimized(true);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1F17),
        body: SafeArea(
          child: Stack(
            children: [
              if (isVideo && _c.phase == CallPhase.active)
                Positioned.fill(
                  child: RTCVideoView(
                    _c.remoteRenderer,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: const Color(0xFF0B6E4F),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : "?",
                          style: const TextStyle(
                            fontSize: 36,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _statusLabel(l10n, peerReachable: peerReachable),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      if (_c.phase == CallPhase.active) ...[
                        const SizedBox(height: 8),
                        Text(
                          _clockLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                      if (_c.phase == CallPhase.active &&
                          _c.icePath != "unknown") ...[
                        const SizedBox(height: 6),
                        Text(
                          _c.icePath == "relay"
                              ? l10n.callPathRelay
                              : l10n.callPathDirect,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (isVideo && _c.phase == CallPhase.active)
                Positioned(
                  top: 16,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      Text(
                        _clockLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (_c.icePath != "unknown")
                        Text(
                          _c.icePath == "relay"
                              ? l10n.callPathRelay
                              : l10n.callPathDirect,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                    ],
                  ),
                ),
              if (isVideo &&
                  (_c.phase == CallPhase.active ||
                      _c.phase == CallPhase.connecting))
                Positioned(
                  right: 16,
                  top: 16,
                  width: 110,
                  height: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: RTCVideoView(
                      _c.localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 32,
                child: _c.phase == CallPhase.ringingIn
                    ? _incomingActions(l10n)
                    : _inCallActions(l10n),
              ),
              Positioned(
                top: 0,
                left: 0,
                child: IconButton(
                  tooltip: l10n.callMinimize,
                  onPressed: _minimize,
                  icon: const Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _incomingActions(L10n l10n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _roundBtn(
          color: Colors.red,
          icon: Icons.call_end,
          label: l10n.callReject,
          onTap: _actionBusy
              ? null
              : () => _safeAction(() => _c.rejectIncoming()),
        ),
        _roundBtn(
          color: const Color(0xFF0B6E4F),
          icon: Icons.call,
          label: l10n.callAccept,
          onTap: _actionBusy
              ? null
              : () => _safeAction(() => _c.acceptIncoming()),
        ),
      ],
    );
  }

  Widget _inCallActions(L10n l10n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _roundBtn(
          color: Colors.white24,
          icon: _c.micMuted ? Icons.mic_off : Icons.mic,
          label: _c.micMuted ? l10n.callMute : l10n.callMic,
          onTap: _actionBusy ? null : () => _safeAction(() => _c.toggleMute()),
        ),
        _roundBtn(
          color: _c.speakerOn ? const Color(0xFF0B6E4F) : Colors.white24,
          icon: _c.speakerOn ? Icons.volume_up : Icons.volume_down,
          label: l10n.callSpeaker,
          onTap: _actionBusy
              ? null
              : () => _safeAction(() => _c.toggleSpeaker()),
        ),
        if (_c.active?.kind == "VIDEO")
          _roundBtn(
            color: Colors.white24,
            icon: _c.camOff ? Icons.videocam_off : Icons.videocam,
            label: l10n.callCamera,
            onTap: _actionBusy
                ? null
                : () => _safeAction(() => _c.toggleCamera()),
          ),
        _roundBtn(
          color: Colors.red,
          icon: Icons.call_end,
          label: l10n.callHangup,
          onTap: _actionBusy ? null : () => _safeAction(() => _c.hangup()),
        ),
      ],
    );
  }

  Widget _roundBtn({
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: CircleAvatar(
            radius: 28,
            backgroundColor: color,
            child: _actionBusy &&
                    (icon == Icons.call_end || icon == Icons.call)
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(icon, color: Colors.white),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}
