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
import "package:klambo_messagerie/core/sound_service.dart";
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
    // `inactive` est trop bruyant (Chrome / focus) — on ne coupe pas le WS.
    // `paused` / `hidden` = vraie sortie du premier plan.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Pause reconnect Flutter ; FGS = filet (appels / interim avant FCM).
      hub?.onAppBackgrounded();
      unawaited(BackgroundAlerts.touch());
      if (hub != null) {
        final phase = hub.controller.phase;
        final inCall = phase == CallPhase.connecting ||
            phase == CallPhase.active ||
            phase == CallPhase.ringingIn ||
            phase == CallPhase.ringingOut;
        unawaited(BackgroundAlerts.ensureAlive());
        if (inCall) {
          final peer = hub.controller.active?.peerName?.trim();
          unawaited(
            BackgroundAlerts.setCallOngoing(
              name: (peer != null && peer.isNotEmpty) ? peer : "Klambo",
              video: hub.controller.active?.kind == "VIDEO",
            ),
          );
        } else {
          // Filet messaging tant que FCM n'est pas branché (pushToken stub).
          final orgId = hub.presence.organizationId;
          if (orgId != null && orgId.isNotEmpty) {
            unawaited(hub.touchPresence());
          }
        }
      }
    } else if (state == AppLifecycleState.inactive) {
      unawaited(BackgroundAlerts.touch());
      if (hub != null &&
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
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(BackgroundAlerts.touch());
      // Revalide les réglages système encore manquants (sans re-popup micro/caméra).
      unawaited(BackgroundAlerts.requestAllPrivileges(runtime: false));
      if (hub != null) {
        // WS reconnect + sync.resume → inbox / fil rattrapent via HTTP.
        hub.onAppResumed();
        unawaited(hub.consumeNativeCall());
        final orgId = hub.presence.organizationId;
        if (orgId != null && orgId.isNotEmpty) {
          unawaited(hub.touchPresence());
          unawaited(hub.refreshPeerPresence(
            organizationId: orgId,
            userId: hub.localUserId,
          ));
        }
      }
      // FGS utile surtout pour les appels ; on le maintient vivant si déjà armé.
      unawaited(BackgroundAlerts.ensureAlive());
    }
    // Uniquement kill process / detach — pas `hidden` (Chrome le tire souvent
    // et coupait l'appel + disposait le media en plein ring).
    if (state == AppLifecycleState.detached) {
      hub?.onAppBackgrounded();
      // Filet natif tant que FCM n'est pas en prod (sinon messages / appels perdus).
      unawaited(BackgroundAlerts.ensureAlive());
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

  /// Arme le filet Android (appels + interim messaging) + préchauffe audio.
  Future<void> _armAlerts() async {
    // Prépare message + ringtone dès l'accueil (évite silence au 1er appel).
    unawaited(SoundService.instance.warmUp());
    if (kIsWeb) return;
    await NotificationService.instance.requestPermissions();
    // FGS d'abord — un seul passage runtime permissions (pas dans start()).
    // Différé pour ne pas « fermer » l'app juste après une MAJ (Réglages).
    await BackgroundAlerts.start();
    await Future<void>.delayed(const Duration(seconds: 4));
    await BackgroundAlerts.requestAllPrivileges();
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
