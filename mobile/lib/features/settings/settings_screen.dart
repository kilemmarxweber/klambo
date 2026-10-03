import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:klambo_messagerie/core/app_version.dart";
import "package:klambo_messagerie/core/alert_prefs.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/core/l10n.dart";
import "package:klambo_messagerie/core/notification_service.dart";
import "package:klambo_messagerie/core/publisher_info.dart";
import "package:klambo_messagerie/core/sound_service.dart";
import "package:klambo_messagerie/core/theme_prefs.dart";
import "package:klambo_messagerie/core/wallpaper_prefs.dart";
import "package:klambo_messagerie/widgets/chat_wallpaper.dart";
import "package:klambo_messagerie/features/auth/phone_login_screen.dart";
import "package:klambo_messagerie/features/auth/session_provider.dart";
import "package:permission_handler/permission_handler.dart";

/// Paramètres système (style Android / WhatsApp) : thème, alertes, à propos…
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _prefs = AlertPrefs.instance;

  Future<void> _setTheme(ThemeMode mode) async {
    await ThemePrefs.instance.setMode(mode);
    if (mounted) setState(() {});
  }

  Future<void> _setWallpaper(WallpaperStyle style) async {
    await WallpaperPrefs.instance.setStyle(style);
    if (mounted) setState(() {});
  }

  void _showAbout() {
    final l10n = ref.read(l10nProvider);
    showAboutDialog(
      context: context,
      applicationName: PublisherInfo.appName,
      applicationVersion: appVersionLabel,
      applicationLegalese:
          "${PublisherInfo.companyLegalName}\n${PublisherInfo.websiteUrl}\n${PublisherInfo.supportEmail}",
      children: [
        const SizedBox(height: 12),
        Text(l10n.verifiedPublisherHint),
        const SizedBox(height: 8),
        SelectableText(
          "${l10n.officialWebsite}: ${PublisherInfo.websiteUrl}",
        ),
        const SizedBox(height: 4),
        SelectableText("Package: ${PublisherInfo.packageId}"),
      ],
    );
  }

  Future<void> _changeContact() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PhoneLoginScreen(changeContact: true),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final l10n = ref.read(l10nProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.logoutApp),
        content: Text(l10n.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.logoutApp),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    unawaited(NotificationService.instance.clearBadge());
    Navigator.of(context).popUntil((route) => route.isFirst);
    await ref.read(sessionProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final scheme = Theme.of(context).colorScheme;
    final themeMode = ThemePrefs.instance.mode;

    return Scaffold(
      backgroundColor: ChatPalette.pageBackground(context),
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        children: [
          _SectionHeader(title: l10n.appearance),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            elevation: 0,
            color: scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: const Icon(Icons.palette_outlined),
              title: Text(l10n.themeTitle),
              subtitle: Text(_themeLabel(l10n, themeMode)),
              childrenPadding: const EdgeInsets.only(bottom: 4),
              children: [
                for (final mode in const [
                  ThemeMode.light,
                  ThemeMode.dark,
                  ThemeMode.system,
                ])
                  ListTile(
                    leading: Icon(_themeIcon(mode)),
                    title: Text(_themeLabel(l10n, mode)),
                    trailing: themeMode == mode
                        ? Icon(Icons.check, color: scheme.primary)
                        : null,
                    onTap: () => unawaited(_setTheme(mode)),
                    dense: true,
                  ),
              ],
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            elevation: 0,
            color: scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.wallpaper_outlined, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.wallpaperTitle,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              l10n.wallpaperHint,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final style in WallpaperStyle.values) ...[
                        if (style != WallpaperStyle.values.first)
                          const SizedBox(width: 8),
                        Expanded(
                          child: _WallpaperChoice(
                            style: style,
                            label: switch (style) {
                              WallpaperStyle.plain => l10n.wallpaperPlain,
                              WallpaperStyle.messages => l10n.wallpaperMessages,
                              WallpaperStyle.android => l10n.wallpaperAndroid,
                              WallpaperStyle.mix => l10n.wallpaperMix,
                            },
                            selected: WallpaperPrefs.instance.style == style,
                            onTap: () => unawaited(_setWallpaper(style)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          _SectionHeader(title: l10n.alertsSettings),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            elevation: 0,
            color: scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ExpansionTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: Text(l10n.notificationsSection),
                  subtitle: Text(l10n.notificationsSectionHint),
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.volume_up_outlined),
                      title: Text(l10n.soundsEnabled),
                      value: _prefs.soundsEnabled,
                      onChanged: (v) async {
                        await _prefs.setSoundsEnabled(v);
                        setState(() {});
                      },
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.chat_bubble_outline),
                      title: Text(l10n.messageAlerts),
                      value: _prefs.messageNotificationsEnabled,
                      onChanged: (v) async {
                        await _prefs.setMessageNotificationsEnabled(v);
                        setState(() {});
                      },
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.call_outlined),
                      title: Text(l10n.callAlerts),
                      value: _prefs.callNotificationsEnabled,
                      onChanged: (v) async {
                        await _prefs.setCallNotificationsEnabled(v);
                        setState(() {});
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.notifications_active_outlined),
                      title: Text(l10n.testMessageSound),
                      subtitle: Text(l10n.testMessageSoundHint),
                      onTap: () async {
                        await SoundService.instance.warmUp();
                        await SoundService.instance.playMessageTone();
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.testMessageSoundDone)),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.app_settings_alt_outlined),
                      title: Text(l10n.systemNotificationSettings),
                      subtitle: Text(l10n.enableAlertsTitle),
                      trailing: const Icon(Icons.open_in_new, size: 18),
                      onTap: () async {
                        await NotificationService.instance.requestPermissions();
                        await openAppSettings();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          _SectionHeader(title: l10n.appSection),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            elevation: 0,
            color: scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(l10n.aboutApp),
                  subtitle: Text(
                    "${PublisherInfo.companyLegalName} · ${PublisherInfo.appName}",
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showAbout,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.sim_card_outlined, color: scheme.primary),
                  title: Text(l10n.changeContact),
                  subtitle: Text(l10n.changeContactHint),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _changeContact,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.logout, color: Colors.red.shade700),
                  title: Text(
                    l10n.logoutApp,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                  onTap: _confirmLogout,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _themeLabel(L10n l10n, ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return l10n.themeLight;
      case ThemeMode.dark:
        return l10n.themeDark;
      case ThemeMode.system:
        return l10n.themeSystem;
    }
  }

  IconData _themeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
      case ThemeMode.system:
        return Icons.phone_android_outlined;
    }
  }
}

class _WallpaperChoice extends StatelessWidget {
  const _WallpaperChoice({
    required this.style,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final WallpaperStyle style;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 108,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 2.5 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ChatWallpaper(style: style),
                if (selected)
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: scheme.primary,
                        child: const Icon(
                          Icons.check,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? scheme.primary : scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: ChatPalette.subtitle(context),
        ),
      ),
    );
  }
}
