# Confiance installation — Klambo (Klambocore SARL)

## Identité

| Champ | Valeur |
|--------|--------|
| App | **Klambo** |
| Éditeur | **Klambocore SARL** |
| Site | **https://klambocore.com** |
| Package Android | `com.klambocore.klambo` |
| Support | support@klambocore.com |

## Signature release

L’APK est signé avec un certificat d’entreprise (pas la clé debug) :

- **CN** = Klambo  
- **O** = Klambocore SARL  
- **OU** = https://klambocore.com  
- **SHA-256** = `B7:D8:8D:0A:61:4A:97:BD:5F:94:3D:7C:D7:D4:42:4C:7A:70:A4:DB:E4:54:06:B0:E5:B3:2A:E7:33:4D:44:C0`

Conservez `android/app/klambo-release.jks` + `android/key.properties` (et la copie Bureau `klambo-signing-backup.txt`) — sans eux, impossible de publier une mise à jour reconnue comme la même app.

## Pourquoi Android affiche encore un avertissement

Sans **Google Play**, Android signale toute installation hors store (« source inconnue »). Ce n’est **pas** un virus : c’est le comportement normal du sideload. Pour supprimer presque toutes les alertes Play Protect :

1. Publier Klambo sur le **Play Store** (compte développeur Google lié à Klambocore SARL).
2. Ou distribuer uniquement depuis **https://klambocore.com** (HTTPS) + page de téléchargement claire.

## À publier sur le site (recommandé)

1. Héberger l’APK : `https://klambocore.com/app/klambo.apk`
2. Page téléchargement avec : nom Klambo, Klambocore SARL, SHA-256 ci-dessus, lien support.
3. Déposer Digital Asset Links :
   - Fichier source : `mobile/docs/assetlinks.json`
   - URL publique : `https://klambocore.com/.well-known/assetlinks.json`
4. Mentions légales / politique de confidentialité sur le même domaine.

## Vérifier l’APK avant install

```bash
keytool -printcert -jarfile klambo.apk
```

L’empreinte SHA-256 doit correspondre à celle du tableau ci-dessus.
