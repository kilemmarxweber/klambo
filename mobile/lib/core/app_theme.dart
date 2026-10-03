import "package:flutter/material.dart";
import "package:flutter/services.dart";

/// Couleurs alignées sur Eteyelo (primary bleu éducatif ~ #2563EB).
abstract final class EteyeloColors {
  static const primary = Color(0xFF2563EB);
  static const primaryDark = Color(0xFF1D4ED8);
  static const primaryDarker = Color(0xFF1E40AF);
  static const accent = Color(0xFF22D3EE);

  static const chatBackground = Color(0xFFF3F0EB);
  static const chatBackgroundDark = Color(0xFF0B141A);
  static const chatInputBar = Color(0xFFF7F6F3);
  static const chatInputBarDark = Color(0xFF1F2C34);

  /// Reçus — à gauche, blanc
  static const bubbleIncoming = Color(0xFFFFFFFF);
  static const bubbleIncomingDark = Color(0xFF1F2C34);
  static const bubbleIncomingBorder = Color(0xFFE6E2DC);
  static const bubbleIncomingBorderDark = Color(0xFF2A3942);
  static const bubbleIncomingText = Color(0xFF1C2430);
  static const bubbleIncomingTextDark = Color(0xFFE9EDEF);

  /// Envoyés — à droite, bleu doux
  static const bubbleOutgoing = Color(0xFFD9E6F7);
  static const bubbleOutgoingDark = Color(0xFF1A3A5C);
  static const bubbleOutgoingBorder = Color(0xFFC5D6EB);
  static const bubbleOutgoingBorderDark = Color(0xFF2A4A6C);
  static const bubbleOutgoingText = Color(0xFF1A2F4A);
  static const bubbleOutgoingTextDark = Color(0xFFE9EDEF);

  static const bubbleMeta = Color(0xFF8A94A6);
  static const listDivider = Color(0xFFE9EDEF);
  static const listDividerDark = Color(0xFF2A3942);
  static const subtitle = Color(0xFF667781);
  static const subtitleDark = Color(0xFF8696A0);
  static const unreadBadge = Color(0xFF25D366);
  static const pageBackground = Color(0xFFF0F2F5);
  static const pageBackgroundDark = Color(0xFF0B141A);
}

ThemeData buildEteyeloTheme({Brightness brightness = Brightness.light}) {
  final isDark = brightness == Brightness.dark;

  final scheme = isDark
      ? const ColorScheme.dark(
          primary: EteyeloColors.primary,
          onPrimary: Colors.white,
          secondary: EteyeloColors.primaryDark,
          surface: Color(0xFF111B21),
          onSurface: Color(0xFFE9EDEF),
          surfaceContainerHighest: Color(0xFF1F2C34),
          outline: Color(0xFF3B4A54),
        )
      : const ColorScheme.light(
          primary: EteyeloColors.primary,
          onPrimary: Colors.white,
          secondary: EteyeloColors.primaryDark,
          surface: Colors.white,
          onSurface: Color(0xFF111B21),
          surfaceContainerHighest: Color(0xFFF0F2F5),
          outline: Color(0xFFCED4DA),
        );

  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: scheme.outline),
  );

  return ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    useMaterial3: true,
    scaffoldBackgroundColor:
        isDark ? EteyeloColors.pageBackgroundDark : Colors.white,
    dividerColor:
        isDark ? EteyeloColors.listDividerDark : EteyeloColors.listDivider,
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: EteyeloColors.primaryDark,
      foregroundColor: Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: Colors.white),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: EteyeloColors.primary,
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(),
      clipBehavior: Clip.none,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: EteyeloColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}

/// Accès rapide aux couleurs de chat selon le thème courant.
abstract final class ChatPalette {
  static Color background(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? EteyeloColors.chatBackgroundDark
          : EteyeloColors.chatBackground;

  static Color inputBar(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? EteyeloColors.chatInputBarDark
          : EteyeloColors.chatInputBar;

  static Color pageBackground(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? EteyeloColors.pageBackgroundDark
          : EteyeloColors.pageBackground;

  static Color subtitle(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? EteyeloColors.subtitleDark
          : EteyeloColors.subtitle;

  static Color divider(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? EteyeloColors.listDividerDark
          : EteyeloColors.listDivider;
}
