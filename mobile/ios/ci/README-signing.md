# Signature iOS (Windows → GitHub Actions)

Bundle ID : `com.klambocore.klamboMessagerie`

## Prérequis

1. Compte [Apple Developer](https://developer.apple.com) (99 $/an)
2. App ID créé pour `com.klambocore.klamboMessagerie`
3. Au moins un appareil UDID enregistré (profil **Ad Hoc**)
4. OpenSSL installé (Git for Windows suffit souvent : `openssl`)

## 1. Créer une CSR + clé (Windows)

```powershell
cd $env:USERPROFILE\Desktop
openssl genrsa -out klambo_dist.key 2048
openssl req -new -key klambo_dist.key -out CertificateSigningRequest.certSigningRequest -subj "/emailAddress=toi@exemple.com/CN=Klambo Distribution/C=FR"
```

## 2. Certificat Apple

1. [Certificates](https://developer.apple.com/account/resources/certificates/list) → **+**
2. Choisir **Apple Distribution**
3. Uploader `CertificateSigningRequest.certSigningRequest`
4. Télécharger `distribution.cer`

Convertir en `.p12` :

```powershell
openssl x509 -in distribution.cer -inform DER -out distribution.pem
openssl pkcs12 -export -out klambo_dist.p12 -inkey klambo_dist.key -in distribution.pem
```

Choisis un mot de passe fort → ce sera le secret `P12_PASSWORD`.

## 3. Profil de provisioning Ad Hoc

1. [Profiles](https://developer.apple.com/account/resources/profiles/list) → **+**
2. **Ad Hoc** → App ID Klambo → certificat Distribution → devices
3. Télécharger `Klambo_AdHoc.mobileprovision`

## 4. Secrets GitHub

Repo → **Settings** → **Secrets and variables** → **Actions** :

| Secret | Comment le remplir |
|--------|--------------------|
| `BUILD_CERTIFICATE_BASE64` | `[Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\Desktop\klambo_dist.p12"))` |
| `P12_PASSWORD` | Mot de passe du `.p12` |
| `PROVISIONING_PROFILE_BASE64` | Même commande PowerShell sur le `.mobileprovision` |
| `KEYCHAIN_PASSWORD` | Mot de passe aléatoire (ex. `openssl rand -base64 16`) |
| `APPLE_TEAM_ID` | Membership → Team ID (10 caractères) |

## 5. Lancer le build

1. Push sur `main` (ou tag `v*`)
2. Onglet **Actions** → **Build iOS IPA** → **Run workflow**
3. Télécharger l’artifact `klambo-ios-ipa`

## TestFlight / App Store plus tard

Dans le workflow, changer `method` de `ad-hoc` vers `app-store` et utiliser un profil **App Store**.
