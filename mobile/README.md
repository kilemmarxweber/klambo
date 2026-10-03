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

## Build iOS (GitHub Actions — Mac cloud)

Impossible de compiler un IPA depuis Windows en local. Utiliser le workflow
[`.github/workflows/build-ios.yml`](../.github/workflows/build-ios.yml) (runner `macos-latest`).

Guide signature détaillé : [`ios/ci/README-signing.md`](ios/ci/README-signing.md).

### Les 5 secrets GitHub à ajouter

Repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret** :

| # | Nom du secret | Valeur |
|---|---------------|--------|
| 1 | `BUILD_CERTIFICATE_BASE64` | Contenu base64 du certificat Distribution `.p12` |
| 2 | `P12_PASSWORD` | Mot de passe choisi à l’export du `.p12` |
| 3 | `PROVISIONING_PROFILE_BASE64` | Contenu base64 du profil Ad Hoc `.mobileprovision` |
| 4 | `KEYCHAIN_PASSWORD` | Mot de passe aléatoire pour la keychain CI (n’importe lequel, fort) |
| 5 | `APPLE_TEAM_ID` | Team ID Apple (10 caractères) — [Membership details](https://developer.apple.com/account) |

### Générer les valeurs (PowerShell)

```powershell
# 1) BUILD_CERTIFICATE_BASE64  (après avoir créé klambo_dist.p12 — voir ios/ci/README-signing.md)
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\Desktop\klambo_dist.p12"))

# 2) P12_PASSWORD → celui saisi pendant : openssl pkcs12 -export ...

# 3) PROVISIONING_PROFILE_BASE64
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\Desktop\Klambo_AdHoc.mobileprovision"))

# 4) KEYCHAIN_PASSWORD
openssl rand -base64 16

# 5) APPLE_TEAM_ID → developer.apple.com → Membership → Team ID
```

### Lancer le build

1. Commit + push des fichiers CI
2. GitHub → **Actions** → **Build iOS IPA** → **Run workflow**
3. Télécharger l’artifact `klambo-ios-ipa`

Bundle ID : `com.klambocore.klamboMessagerie`

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
