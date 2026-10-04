import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:klambo_messagerie/core/l10n.dart";
import "package:klambo_messagerie/features/calls/call_controller.dart";
import "package:klambo_messagerie/features/calls/call_hub.dart";

/// Bandeau au-dessus de l'app tant que l'appel est réduit.
/// Un tap rouvre la fenêtre, sans couper la voix.
class CallShell extends ConsumerStatefulWidget {
  const CallShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CallShell> createState() => _CallShellState();
}

class _CallShellState extends ConsumerState<CallShell> {
  CallController? _controller;

  @override
  void dispose() {
    _controller?.removeListener(_onCall);
    super.dispose();
  }

  void _onCall() {
    if (mounted) setState(() {});
  }

  void _sync(CallController? next) {
    if (identical(_controller, next)) return;
    _controller?.removeListener(_onCall);
    _controller = next;
    _controller?.addListener(_onCall);
  }

  @override
  Widget build(BuildContext context) {
    final hub = ref.watch(callHubProvider);
    _sync(hub?.controller);
    final call = _controller;
    final show = call != null &&
        !call.isDisposed &&
        call.isBusy &&
        call.minimized;
    final mq = MediaQuery.of(context);
    final barHeight = show ? 44.0 : 0.0;

    return MediaQuery(
      data: mq.copyWith(
        padding: mq.padding.copyWith(top: mq.padding.top + barHeight),
      ),
      child: Stack(
        children: [
          widget.child,
          if (show)
            Positioned(
              top: mq.padding.top,
              left: 0,
              right: 0,
              height: barHeight,
              child: _CallReturnBar(
                controller: call,
                onTap: () => hub?.showCallScreen(),
              ),
            ),
        ],
      ),
    );
  }
}

class _CallReturnBar extends ConsumerWidget {
  const _CallReturnBar({required this.controller, required this.onTap});

  final CallController controller;
  final VoidCallback onTap;

  String _caption(L10n l10n) {
    final raw = controller.active?.peerName?.trim();
    final name =
        (raw != null && raw.isNotEmpty) ? raw : l10n.callPeerFallback;
    if (controller.phase == CallPhase.active) {
      return "$name · ${controller.callClockLabel}";
    }
    if (controller.phase == CallPhase.ringingOut) {
      return "$name · ${l10n.callPeerAway}";
    }
    if (controller.phase == CallPhase.connecting) {
      return name;
    }
    if (controller.phase == CallPhase.ringingIn) {
      return "$name · ${l10n.callRingingIn}";
    }
    return "$name · ${l10n.callPeerAway}";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final video = controller.active?.kind == "VIDEO";
    return Material(
      color: const Color(0xFF0B6E4F),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                video ? Icons.videocam : Icons.call,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _caption(l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const Icon(Icons.keyboard_arrow_up, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
