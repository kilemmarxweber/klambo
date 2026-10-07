import "dart:math" as math;

import "package:flutter/material.dart";
import "package:klambo_messagerie/core/app_theme.dart";

/// Points animés en sinusoïde (style WhatsApp) — « en train d'écrire ».
///
/// Utilise [AnimationController.repeat] + [AnimatedBuilder] (docs Flutter).
/// Couleur alpha plutôt que widget [Opacity] (coût GPU plus faible).
class TypingDots extends StatefulWidget {
  const TypingDots({
    super.key,
    this.color = const Color(0xFF667781),
    this.size = 7,
    this.gap = 3.5,
    this.amplitude = 3.2,
  });

  final Color color;
  final double size;
  final double gap;

  /// Amplitude verticale du mouvement sinusoïdal (px).
  final double amplitude;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // ~1,1 s : rythme proche WhatsApp, fluide sans saccades.
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
    final h = widget.size + widget.amplitude * 2;
    return SizedBox(
      height: h,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value * 2 * math.pi;
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(3, (i) {
              // Déphasage 120° : vague sinusoïdale continue.
              final wave = math.sin(t - i * (2 * math.pi / 3));
              final lift = (wave + 1) / 2; // 0 → 1
              final dy = -lift * widget.amplitude;
              final scale = 0.78 + lift * 0.32;
              final alpha = 0.38 + lift * 0.62;
              return Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : widget.gap),
                child: Transform.translate(
                  offset: Offset(0, dy),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: alpha),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// Bulle discrète avec points sinusoïdaux (bas du fil de messages).
class TypingBubble extends StatelessWidget {
  const TypingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        liveRegion: true,
        label: "En train d'écrire",
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 2, 48, 8),
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 9),
          decoration: BoxDecoration(
            color: dark
                ? EteyeloColors.bubbleIncomingDark
                : EteyeloColors.bubbleIncoming,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(18),
            ),
            border: Border.all(
              color: dark
                  ? EteyeloColors.bubbleIncomingBorderDark
                  : EteyeloColors.bubbleIncomingBorder,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.18 : 0.05),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: const TypingDots(
            color: Color(0xFF8696A0),
            size: 8,
            gap: 4,
            amplitude: 3.6,
          ),
        ),
      ),
    );
  }
}

/// Ligne compacte pour la liste des conversations — points verts uniquement.
class TypingListPreview extends StatelessWidget {
  const TypingListPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const TypingDots(
      color: Color(0xFF25D366),
      size: 6,
      gap: 3,
      amplitude: 2.4,
    );
  }
}

/// Sous-titre app bar : points blancs + « écrit… ».
class TypingAppBarSubtitle extends StatelessWidget {
  const TypingAppBarSubtitle({super.key, this.label = "écrit…"});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TypingDots(
          color: Colors.white.withValues(alpha: 0.92),
          size: 5,
          gap: 2.5,
          amplitude: 2.0,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }
}
