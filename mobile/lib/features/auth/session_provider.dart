import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:klambo_messagerie/core/app_exit.dart";
import "package:klambo_messagerie/core/background_alerts.dart";
import "package:klambo_messagerie/data/api_client.dart";
import "package:klambo_messagerie/data/auth_repository.dart";
import "package:klambo_messagerie/data/messaging_repository.dart";

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);

final messagingRepositoryProvider = Provider<MessagingRepository>(
  (ref) => MessagingRepository(ref.watch(apiClientProvider)),
);

class SessionState {
  const SessionState({
    this.token,
    this.me,
    this.loading = true,
  });

  final String? token;
  final Map<String, dynamic>? me;
  final bool loading;

  bool get isAuthenticated => token != null && token!.isNotEmpty;
  bool get needsOnboarding => me?["needsOnboarding"] == true;
  String? get activeOrgId => me?["activeOrganizationId"]?.toString();

  List<Map<String, dynamic>> get organizations {
    final raw = me?["organizations"];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Orgs où la messagerie Eteyelo est lisible (mêmes threads que le web).
  List<Map<String, dynamic>> get messagingOrganizations {
    return organizations.where((o) {
      if (o["messagingEnabled"] == false) return false;
      if (o["canRead"] == false) return false;
      return o["id"] != null;
    }).toList();
  }
}

class SessionNotifier extends StateNotifier<SessionState> {
  SessionNotifier(this._auth, this._api) : super(const SessionState()) {
    _bootstrap();
  }

  final AuthRepository _auth;
  final ApiClient _api;

  Future<void> _bootstrap() async {
    final token = await _api.getToken();
    if (token == null || token.isEmpty) {
      state = const SessionState(loading: false);
      return;
    }

    // Restaure immédiatement l'UI depuis le cache local (pas de re-OTP).
    final cached = await _api.getMeSnapshot();
    if (cached != null) {
      state = SessionState(token: token, me: cached, loading: false);
    }

    try {
      final me = await _auth.me();
      await _api.saveMeSnapshot(me);
      state = SessionState(token: token, me: me, loading: false);
    } catch (e) {
      // Ne déconnecte que si le serveur refuse explicitement le token.
      final unauthorized = e is ApiException && e.isUnauthorized;
      if (unauthorized) {
        await _api.clearToken();
        state = const SessionState(loading: false);
        return;
      }
      // Réseau / serveur down : garde la session locale ouverte.
      if (cached != null) {
        state = SessionState(token: token, me: cached, loading: false);
      } else {
        // Token présent mais pas encore de cache : reste connecté, UI minimale.
        state = SessionState(
          token: token,
          me: {
            "needsOnboarding": false,
            "profileComplete": true,
            "user": {"name": "…"},
            "organizations": [],
            "activeOrganizationId": null,
          },
          loading: false,
        );
      }
    }
  }

  Future<void> applyAuthPayload(Map<String, dynamic> data) async {
    final token = data["token"]?.toString() ?? await _api.getToken();
    if (token != null && token.isNotEmpty) {
      await _api.saveToken(token);
    }
    await _api.saveMeSnapshot(data);
    state = SessionState(token: token, me: data, loading: false);
  }

  Future<void> refreshMe() async {
    final me = await _auth.me();
    await _api.saveMeSnapshot(me);
    state = SessionState(token: state.token, me: me, loading: false);
  }

  Future<void> setActiveOrganization(String organizationId) async {
    final me = await _auth.setActiveOrganization(organizationId);
    await _api.saveMeSnapshot(me);
    state = SessionState(token: state.token, me: me, loading: false);
  }

  Future<void> signOut({bool exitAppAfter = false}) async {
    await BackgroundAlerts.stop();
    await _auth.signOut();
    state = const SessionState(loading: false);
    if (exitAppAfter) {
      await exitApp();
    }
  }
}

final sessionProvider =
    StateNotifierProvider<SessionNotifier, SessionState>((ref) {
  return SessionNotifier(
    ref.watch(authRepositoryProvider),
    ref.watch(apiClientProvider),
  );
});
