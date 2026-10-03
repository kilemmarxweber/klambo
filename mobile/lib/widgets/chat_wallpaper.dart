import "package:flutter/material.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/core/wallpaper_prefs.dart";

/// Fond de discussion : une seule couleur, motifs en trait de la même teinte.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key, this.style});

  /// Si null, utilise le style enregistré dans l'application.
  final WallpaperStyle? style;

  static Color baseFor(BuildContext context, [WallpaperStyle? style]) {
    final value = style ?? WallpaperPrefs.instance.style;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return baseOf(value, dark: dark);
  }

  /// Le fond Android reste sombre, même si le thème de l’app est clair.
  static bool surfaceDark(WallpaperStyle style, {required bool dark}) {
    return style == WallpaperStyle.android || dark;
  }

  static Color baseOf(WallpaperStyle style, {required bool dark}) {
    final useDark = surfaceDark(style, dark: dark);
    return switch (style) {
      WallpaperStyle.plain ||
      WallpaperStyle.messages ||
      WallpaperStyle.android ||
      WallpaperStyle.mix =>
        useDark ? EteyeloColors.chatBackgroundDark : EteyeloColors.chatBackground,
    };
  }

  /// Encre du filigrane : trait clair sur fond sombre, trait sombre sur fond clair.
  static Color watermarkOf(WallpaperStyle style, {required bool dark}) {
    if (style == WallpaperStyle.plain) return const Color(0x00000000);
    if (surfaceDark(style, dark: dark)) {
      return Colors.white.withValues(alpha: 0.22);
    }
    return const Color(0xFF5C534C).withValues(alpha: 0.28);
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
    final dark = surfaceDark(
      value,
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    final base = baseOf(value, dark: dark);
    if (value == WallpaperStyle.plain) {
      return ColoredBox(color: base, child: const SizedBox.expand());
    }
    return ColoredBox(
      color: base,
      child: IgnorePointer(
        child: _DoodleField(
          style: value,
          color: watermarkOf(value, dark: dark),
        ),
      ),
    );
  }
}

class _DoodleField extends StatelessWidget {
  const _DoodleField({required this.style, required this.color});

  final WallpaperStyle style;
  final Color color;

  static const _step = 52.0;

  static const _messages = <IconData>[
    Icons.chat_bubble_outline,
    Icons.phone_outlined,
    Icons.mail_outline,
    Icons.photo_camera_outlined,
    Icons.favorite_border,
    Icons.mic_none_outlined,
    Icons.attach_file,
    Icons.emoji_emotions_outlined,
    Icons.sticky_note_2_outlined,
    Icons.groups_outlined,
  ];

  static const _android = <IconData>[
    Icons.phone_android,
    Icons.settings_outlined,
    Icons.notifications_none,
    Icons.battery_std,
    Icons.wifi,
    Icons.videocam_outlined,
    Icons.sports_esports_outlined,
    Icons.headphones,
  ];

  static const _mix = <IconData>[
    Icons.chat_bubble_outline,
    Icons.phone_outlined,
    Icons.photo_camera_outlined,
    Icons.favorite_border,
    Icons.videocam_outlined,
    Icons.image_outlined,
    Icons.mic_none_outlined,
    Icons.location_on_outlined,
    Icons.emoji_emotions_outlined,
    Icons.headphones_outlined,
    Icons.music_note_outlined,
    Icons.mail_outline,
    Icons.shopping_bag_outlined,
    Icons.local_cafe_outlined,
    Icons.attach_file,
    Icons.cake_outlined,
    Icons.thumb_up_alt_outlined,
    Icons.flight_outlined,
    Icons.pets_outlined,
    Icons.wb_sunny_outlined,
  ];

  List<IconData> get _icons => switch (style) {
        WallpaperStyle.plain => const [],
        WallpaperStyle.messages => _messages,
        WallpaperStyle.android => _android,
        WallpaperStyle.mix => _mix,
      };

  @override
  Widget build(BuildContext context) {
    final icons = _icons;
    if (icons.isEmpty) return const SizedBox.expand();
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
        for (var y = 4.0; y < height; y += _step) {
          final shift = row.isOdd ? _step / 2 : 0.0;
          for (var x = -_step / 2; x < width; x += _step) {
            final icon = icons[index % icons.length];
            final size = 18.0 + (index % 3) * 2;
            children.add(
              Positioned(
                left: x + shift,
                top: y,
                child: Icon(icon, size: size, color: color),
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
