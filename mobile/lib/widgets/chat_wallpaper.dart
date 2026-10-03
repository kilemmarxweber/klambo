import "package:flutter/material.dart";
import "package:klambo_messagerie/core/wallpaper_prefs.dart";

/// Fond de discussion généré : emojis téléphone, Android, enveloppes, etc.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key, this.style});

  /// Si null, utilise le style enregistré dans l'application.
  final WallpaperStyle? style;

  static Color baseFor(BuildContext context, [WallpaperStyle? style]) {
    final value = style ?? WallpaperPrefs.instance.style;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return baseOf(value, dark: dark);
  }

  static Color baseOf(WallpaperStyle style, {required bool dark}) {
    return switch (style) {
      WallpaperStyle.messages =>
        dark ? const Color(0xFF102033) : const Color(0xFFE7F2FC),
      WallpaperStyle.android =>
        dark ? const Color(0xFF102018) : const Color(0xFFE6F6EE),
      WallpaperStyle.mix =>
        dark ? const Color(0xFF24180F) : const Color(0xFFFFF3E6),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (style != null) {
      return _paint(context, style!);
    }
    return ListenableBuilder(
      listenable: WallpaperPrefs.instance,
      builder: (context, _) => _paint(context, WallpaperPrefs.instance.style),
    );
  }

  Widget _paint(BuildContext context, WallpaperStyle value) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: _EmojiWallpaperPainter(style: value, dark: dark),
      child: const SizedBox.expand(),
    );
  }
}

class _Spot {
  const _Spot(this.emoji, this.dx, this.dy, this.size);
  final String emoji;
  final double dx;
  final double dy;
  final double size;
}

class _EmojiWallpaperPainter extends CustomPainter {
  _EmojiWallpaperPainter({required this.style, required this.dark});

  final WallpaperStyle style;
  final bool dark;

  static const _tile = 180.0;

  List<_Spot> get _spots => switch (style) {
        WallpaperStyle.messages => const [
            _Spot("✉️", 10, 14, 26),
            _Spot("📱", 78, 22, 28),
            _Spot("💬", 138, 8, 22),
            _Spot("📞", 28, 96, 24),
            _Spot("💌", 108, 108, 26),
            _Spot("📲", 148, 72, 18),
          ],
        WallpaperStyle.android => const [
            _Spot("🤖", 12, 12, 30),
            _Spot("📱", 92, 18, 24),
            _Spot("💚", 142, 78, 20),
            _Spot("🔔", 36, 104, 22),
            _Spot("✉️", 112, 112, 24),
            _Spot("🕹️", 150, 28, 18),
          ],
        WallpaperStyle.mix => const [
            _Spot("📱", 8, 12, 24),
            _Spot("🤖", 72, 6, 26),
            _Spot("✉️", 132, 22, 22),
            _Spot("💬", 18, 96, 22),
            _Spot("📷", 78, 104, 22),
            _Spot("✨", 138, 92, 18),
            _Spot("💙", 156, 48, 16),
            _Spot("📎", 48, 52, 16),
          ],
      };

  @override
  void paint(Canvas canvas, Size size) {
    final base = ChatWallpaper.baseOf(style, dark: dark);
    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = Color.fromARGB(dark ? 150 : 170, 255, 255, 255),
    );
    for (var y = -8.0; y < size.height + _tile; y += _tile) {
      for (var x = -12.0; x < size.width + _tile; x += _tile) {
        for (final spot in _spots) {
          final painter = TextPainter(
            text: TextSpan(
              text: spot.emoji,
              style: TextStyle(fontSize: spot.size, height: 1),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          painter.paint(canvas, Offset(x + spot.dx, y + spot.dy));
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EmojiWallpaperPainter oldDelegate) {
    return oldDelegate.style != style || oldDelegate.dark != dark;
  }
}
