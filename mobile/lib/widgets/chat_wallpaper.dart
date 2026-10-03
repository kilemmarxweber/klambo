import "package:flutter/material.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/core/wallpaper_prefs.dart";

/// Fond de discussion : une seule couleur, emojis en filigrane de la même teinte.
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
      WallpaperStyle.plain ||
      WallpaperStyle.messages ||
      WallpaperStyle.android ||
      WallpaperStyle.mix =>
        dark ? EteyeloColors.chatBackgroundDark : EteyeloColors.chatBackground,
    };
  }

  /// Encre du filigrane : même teinte que le fond, un cran plus marquée.
  static Color watermarkOf(WallpaperStyle style, {required bool dark}) {
    if (style == WallpaperStyle.plain) return const Color(0x00000000);
    final base = baseOf(style, dark: dark);
    final ink = dark ? Colors.white : const Color(0xFF6B6258);
    return Color.alphaBlend(ink.withValues(alpha: dark ? 0.20 : 0.28), base);
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
    final base = baseOf(value, dark: dark);
    if (value == WallpaperStyle.plain) {
      return ColoredBox(color: base, child: const SizedBox.expand());
    }
    final ink = watermarkOf(value, dark: dark);
    return ColoredBox(
      color: base,
      child: IgnorePointer(
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
          child: _EmojiField(style: value),
        ),
      ),
    );
  }
}

class _EmojiField extends StatelessWidget {
  const _EmojiField({required this.style});

  final WallpaperStyle style;

  static const _size = 18.0;
  static const _step = 46.0;
  static const _fonts = [
    "Segoe UI Emoji",
    "Apple Color Emoji",
    "Noto Color Emoji",
    "Noto Emoji",
  ];

  static const _messages = [
    "💬", "✉️", "📱", "📞", "💌", "📲", "💭", "📧",
    "🗨️", "☎️", "📩", "📨", "📝", "💜", "💙", "📎",
  ];

  static const _android = [
    "🤖", "📱", "💚", "🔔", "🕹️", "⚙️", "📲", "💻",
    "🔋", "📡", "🟢", "📳", "🔌", "📟", "🖱️", "🤖",
  ];

  static const _mix = [
    "💬", "🤖", "✉️", "📷", "✨", "💙", "📎", "⭐",
    "📱", "🎉", "❤️", "😂", "👍", "🌈", "🔥", "☕",
    "🌙", "🌸", "🎯", "🎵", "📍", "🌟", "📞", "💚",
  ];

  List<String> get _emojis => switch (style) {
        WallpaperStyle.plain => const [],
        WallpaperStyle.messages => _messages,
        WallpaperStyle.android => _android,
        WallpaperStyle.mix => _mix,
      };

  @override
  Widget build(BuildContext context) {
    final emojis = _emojis;
    if (emojis.isEmpty) return const SizedBox.expand();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
          return const SizedBox.expand();
        }
        final children = <Widget>[];
        var index = 0;
        var row = 0;
        for (var y = 0.0; y < height; y += _step) {
          final shift = row.isOdd ? _step / 2 : 0.0;
          for (var x = -_step / 2; x < width; x += _step) {
            children.add(
              Positioned(
                left: x + shift,
                top: y,
                child: Text(
                  emojis[index % emojis.length],
                  style: const TextStyle(
                    fontSize: _size,
                    height: 1,
                    fontFamilyFallback: _fonts,
                  ),
                ),
              ),
            );
            index++;
          }
          row++;
        }
        return Stack(clipBehavior: Clip.hardEdge, children: children);
      },
    );
  }
}
