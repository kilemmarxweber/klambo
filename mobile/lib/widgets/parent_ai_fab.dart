import "dart:math" as math;

import "package:flutter/material.dart";
import "package:klambo_messagerie/core/app_theme.dart";

/// Accès rapide « Espace parent » — halo animé type assistant IA.
class ParentAiFab extends StatefulWidget {
  const ParentAiFab({
    super.key,
    required this.onPressed,
    this.tooltip = "Espace parent",
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  State<ParentAiFab> createState() => _ParentAiFabState();
}

class _ParentAiFabState extends State<ParentAiFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: SizedBox(
        width: 56,
        height: 56,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final t = _pulse.value;
            final glow = 0.25 + 0.2 * math.sin(t * math.pi * 2);
            final scale = 1.0 + 0.06 * math.sin(t * math.pi * 2);
            return Stack(
              alignment: Alignment.center,
              children: [
                Transform.scale(
                  scale: 1.0 + t * 0.22,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: EteyeloColors.primary.withValues(
                          alpha: (1 - t) * 0.45,
                        ),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                Transform.scale(
                  scale: scale,
                  child: Material(
                    elevation: 4 + glow * 8,
                    shadowColor: EteyeloColors.primary.withValues(alpha: 0.5),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onPressed,
                      customBorder: const CircleBorder(),
                      child: Ink(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.lerp(
                                EteyeloColors.primary,
                                const Color(0xFF6366F1),
                                0.35 + 0.15 * math.sin(t * math.pi * 2),
                              )!,
                              EteyeloColors.primaryDark,
                            ],
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.family_restroom_rounded,
                              color: Colors.white.withValues(alpha: 0.92),
                              size: 22,
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Transform.rotate(
                                angle: t * math.pi * 2,
                                child: Icon(
                                  Icons.auto_awesome,
                                  size: 11,
                                  color: Colors.white.withValues(
                                    alpha: 0.85 + 0.15 * math.sin(t * math.pi * 4),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
