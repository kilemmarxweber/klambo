import "dart:math" as math;

import "package:flutter/material.dart";

/// Anneau léger qui tourne pendant la négociation du lien.
/// Un seul ticker, peint dans un petit carré, sans texte.
class CallConnectPulse extends StatefulWidget {
  const CallConnectPulse({super.key});

  @override
  State<CallConnectPulse> createState() => _CallConnectPulseState();
}

class _CallConnectPulseState extends State<CallConnectPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 44,
        height: 44,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return CustomPaint(
              painter: _PulsePainter(_ctrl.value),
            );
          },
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0x55FFFFFF),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      t * math.pi * 2,
      math.pi * 0.85,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white,
    );
    for (var i = 0; i < 3; i++) {
      final angle = (t + i / 3) * math.pi * 2;
      final phase = (t + i * 0.18) % 1.0;
      final bounce = phase < 0.5 ? phase * 2 : 1 - (phase - 0.5) * 2;
      final dot = center +
          Offset(math.cos(angle) * (radius - 8), math.sin(angle) * (radius - 8));
      canvas.drawCircle(
        dot,
        2.1 + bounce * 1.3,
        Paint()..color = Colors.white.withValues(alpha: 0.4 + bounce * 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) => oldDelegate.t != t;
}
