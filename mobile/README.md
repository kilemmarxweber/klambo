# Klambo Messagerie (Flutter)

App mobile WhatsApp-like branchée sur l’API Eteyelo `/api/mobile/v1`.

## Prérequis

1. Installer [Flutter](https://docs.flutter.dev/get-started/install/windows) (SDK 3.24+).
2. Eteyelo en local (`pnpm dev`) avec Better Auth + Postgres.
3. Variable `MESSAGING_API_KEY` sur Eteyelo pour l’envoi OTP SMS (sinon le code OTP est loggé côté serveur en DEV).

## Bootstrap

```bash
cd C:\Users\kilemmarxweber\Desktop\klambo\mobile
flutter create . --project-name klambo_messagerie --org com.klambocore
flutter pub get
flutter run
```

Si le dossier contient déjà les sources `lib/`, `flutter create .` complète `android/` / `ios/` sans écraser `lib/`.

## Build APK (Windows / Linux / macOS)

```bash
# APK léger (arm64 uniquement) — signé Klambocore SARL
flutter build apk --release --target-platform android-arm64 \
  --dart-define=API_BASE_URL=https://klambocore.com
# → build/app/outputs/flutter-apk/app-release.apk → Desktop/klambo.apk
```

Confiance / sideload : voir `docs/INSTALL_TRUST.md` (éditeur, SHA-256, assetlinks).
Minify R8 + `abiFilters arm64-v8a` sont activés en release (`android/app/build.gradle.kts`).
Le poids restant vient surtout de WebRTC (appels).

## Build iOS (macOS + Xcode uniquement)

Impossible depuis Windows. Sur un Mac :

```bash
cd mobile
flutter pub get
cd ios && pod install && cd ..
flutter build ipa --release
# IPA : build/ios/ipa/*.ipa — renommer en klambo.ipa
```

Compte Apple Developer + signing requis pour installer sur appareil / TestFlight.

## Alertes (sons + notifications + badge)

- Sons in-app : `assets/sounds/message.wav` + `ringtone.wav` (+ `res/raw/ringtone.wav` Android)
- Après connexion : demande d’autorisation notifications
- Messages / appels : canaux Android `klambo_messages_v4` / `klambo_calls_v4`
- Badge : bump local + sync API (ne s’efface plus si le poll est encore à 0)
- Réglages : menu compte → Sons / Notifications messages / Appels
- Temps réel = WebSocket : l’autre téléphone doit avoir Klambo **ouvert ou en arrière-plan**

> Push FCM (app **tuée** / écran verrouillé long) nécessite un projet Firebase + `google-services.json` et l’envoi côté Eteyelo. Sans ça, messages/appels n’arrivent pas si le process Android est mort.

## Config

`lib/core/config.dart` — source Eteyelo :

- **Release** : `https://klambocore.com` par défaut
- **Debug** : `http://10.0.2.2:3000` (émulateur Android) / `localhost` (web/desktop)
- **Compile-time** : `flutter build apk --dart-define=API_BASE_URL=https://…`
- **Runtime** : icône ⚙ sur l’écran téléphone → saisir / presets (Prod, Émulateur, Localhost)

## Auth

1. Saisie téléphone → `POST /api/mobile/v1/auth/otp/request`
2. OTP → `POST /api/mobile/v1/auth/otp/verify` → token Bearer
3. Si `needsOnboarding` → profil (nom + photo) → `POST /api/mobile/v1/auth/profile`
4. Conversations via `/api/mobile/v1/organizations/:orgId/...`
