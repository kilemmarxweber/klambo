import "package:flutter/material.dart";
import "package:klambo_messagerie/core/app_theme.dart";

/// Points animés verts — indicateur « en train d'écrire ».
class TypingDots extends StatefulWidget {
  const TypingDots({
    super.key,
    this.color = EteyeloColors.unreadBadge,
    this.size = 7,
    this.gap = 4,
  });

  final Color color;
  final double size;
  final double gap;

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
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
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_ctrl.value + i * 0.18) % 1.0;
            final bounce = (phase < 0.5)
                ? (phase * 2)
                : (1 - (phase - 0.5) * 2);
            final opacity = 0.35 + bounce * 0.65;
            final dy = -bounce * 3.5;
            return Padding(
              padding: EdgeInsets.only(
                left: i == 0 ? 0 : widget.gap,
              ),
              child: Transform.translate(
                offset: Offset(0, dy),
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Bulle discrète avec points verts (bas du fil de messages).
class TypingBubble extends StatelessWidget {
  const TypingBubble({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 2, 48, 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: dark
              ? EteyeloColors.bubbleIncomingDark
              : EteyeloColors.bubbleIncoming,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(
            color: dark
                ? EteyeloColors.bubbleIncomingBorderDark
                : EteyeloColors.bubbleIncomingBorder,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: const TypingDots(),
      ),
    );
  }
}
