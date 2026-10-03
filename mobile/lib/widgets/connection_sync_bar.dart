import "package:flutter/material.dart";
import "package:klambo_messagerie/core/app_theme.dart";

/// Bandeau de sync non bloquant (style Turbo) — remplace le texte « hors ligne ».
class ConnectionSyncBar extends StatefulWidget {
  const ConnectionSyncBar({super.key});

  @override
  State<ConnectionSyncBar> createState() => _ConnectionSyncBarState();
}

class _ConnectionSyncBarState extends State<ConnectionSyncBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        height: 3,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return CustomPaint(
              painter: _TurboProgressPainter(
                progress: _ctrl.value,
                color: EteyeloColors.primary,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TurboProgressPainter extends CustomPainter {
  _TurboProgressPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()..color = color.withValues(alpha: 0.12);
    canvas.drawRect(Offset.zero & size, track);

    final barWidth = size.width * 0.38;
    final travel = size.width + barWidth;
    final x = progress * travel - barWidth;

    final rect = Rect.fromLTWH(x, 0, barWidth, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0.05),
          color.withValues(alpha: 0.95),
          color.withValues(alpha: 0.05),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _TurboProgressPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
