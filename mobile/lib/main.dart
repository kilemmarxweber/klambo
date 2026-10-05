import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:klambo_messagerie/core/alert_prefs.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/core/background_alerts.dart";
import "package:klambo_messagerie/core/config.dart";
import "package:klambo_messagerie/core/data_saver_prefs.dart";
import "package:klambo_messagerie/core/l10n.dart";
import "package:klambo_messagerie/core/notification_service.dart";
import "package:klambo_messagerie/core/theme_prefs.dart";
import "package:klambo_messagerie/core/wallpaper_prefs.dart";
import "package:klambo_messagerie/features/auth/phone_login_screen.dart";
import "package:klambo_messagerie/features/auth/profile_onboarding_screen.dart";
import "package:klambo_messagerie/features/auth/session_provider.dart";
import "package:klambo_messagerie/features/calls/call_controller.dart";
import "package:klambo_messagerie/features/calls/call_hub.dart";
import "package:klambo_messagerie/features/calls/call_return_bar.dart";
import "package:klambo_messagerie/features/conversations/conversations_screen.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint("[flutter] ${details.exceptionAsString()}");
  };
  try {
    await Future.wait([
      AppConfig.loadPersisted(),
      LocaleController.instance.loadPersisted(),
      AlertPrefs.instance.load(),
      ThemePrefs.instance.load(),
      DataSaverPrefs.instance.load(),
      WallpaperPrefs.instance.load(),
    ]);
  } catch (e, st) {
    debugPrint("[boot] prefs failed: $e\n$st");
  }
  try {
    await NotificationService.instance.init();
  } catch (e, st) {
    debugPrint("[boot] notifications init failed: $e\n$st");
  }
  runApp(const ProviderScope(child: KlamboMessagerieApp()));
}

class KlamboMessagerieApp extends ConsumerStatefulWidget {
  const KlamboMessagerieApp({super.key});

  @override
  ConsumerState<KlamboMessagerieApp> createState() =>
      _KlamboMessagerieAppState();
}

class _KlamboMessagerieAppState extends ConsumerState<KlamboMessagerieApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ThemePrefs.instance.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    ThemePrefs.instance.removeListener(_onThemeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    NotificationService.instance.setLifecycle(state);
    final hub = ref.read(callHubProvider);
    // Retour premier plan / sortie d'arrière-plan : reconnecte le WS
    // pour recevoir messages + appels dès que l'app n'est plus gelée.
    if (state == AppLifecycleState.resumed) {
      unawaited(BackgroundAlerts.touch());
    }
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        hub != null &&
        (hub.controller.phase == CallPhase.connecting ||
            hub.controller.phase == CallPhase.active)) {
      final peer = hub.controller.active?.peerName?.trim();
      unawaited(
        BackgroundAlerts.setCallOngoing(
          name: (peer != null && peer.isNotEmpty) ? peer : "Klambo",
          video: hub.controller.active?.kind == "VIDEO",
        ),
      );
    }
    if (state == AppLifecycleState.resumed && hub != null) {
      unawaited(hub.consumeNativeCall());
      if (!hub.socket.isConnected) {
        hub.socket.reconnectNow();
      }
      final orgId = hub.presence.organizationId;
      if (orgId != null && orgId.isNotEmpty) {
        unawaited(hub.refreshPeerPresence(
          organizationId: orgId,
          userId: hub.localUserId,
        ));
      }
    }
    // Uniquement kill process / detach — pas `hidden` (Chrome le tire souvent
    // et coupait l'appel + disposait le media en plein ring).
    if (state == AppLifecycleState.detached) {
      if (hub != null) {
        unawaited(hub.onAppClosing());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: "Klambo Messagerie",
      debugShowCheckedModeBanner: false,
      theme: buildEteyeloTheme(brightness: Brightness.light),
      darkTheme: buildEteyeloTheme(brightness: Brightness.dark),
      themeMode: ThemePrefs.instance.mode,
      builder: (context, child) {
        return CallShell(child: child ?? const SizedBox.shrink());
      },
      home: const RootGate(),
    );
  }
}

class RootGate extends ConsumerStatefulWidget {
  const RootGate({super.key});

  @override
  ConsumerState<RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<RootGate> {
  bool _alertsArmed = false;

  /// Active le son système dès l'ouverture, sans écran de réglages.
  /// Android 13+ affiche une seule fois la demande système des notifications.
  Future<void> _armAlerts() async {
    if (kIsWeb) return;
    final allowed =
        await NotificationService.instance.areNotificationsAllowed();
    if (!allowed) {
      await NotificationService.instance.requestPermissions();
    }
    await BackgroundAlerts.start();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    Widget child;
    if (session.loading) {
      child = const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    } else if (!session.isAuthenticated) {
      child = const PhoneLoginScreen();
    } else if (session.needsOnboarding) {
      child = const ProfileOnboardingScreen();
    } else {
      ref.watch(callHubProvider);

      if (!_alertsArmed) {
        _alertsArmed = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_armAlerts());
        });
      }
      child = const ConversationsScreen();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: KeyedSubtree(
        key: ValueKey(
          session.loading
              ? "loading"
              : !session.isAuthenticated
                  ? "login"
                  : session.needsOnboarding
                      ? "onboarding"
                      : "home",
        ),
        child: child,
      ),
    );
  }
}
