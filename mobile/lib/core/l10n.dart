import "package:flutter/foundation.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:shared_preferences/shared_preferences.dart";

enum AppLang {
  fr,
  en,
  pt;

  String get code => name;

  static AppLang fromCode(String? raw) {
    switch (raw?.toLowerCase()) {
      case "en":
        return AppLang.en;
      case "pt":
        return AppLang.pt;
      default:
        return AppLang.fr;
    }
  }
}

/// Traductions légères FR (défaut) / EN / PT.
class L10n {
  L10n(this.lang);

  final AppLang lang;

  static L10n of(AppLang lang) => L10n(lang);

  String _t(String fr, String en, String pt) {
    switch (lang) {
      case AppLang.en:
        return en;
      case AppLang.pt:
        return pt;
      case AppLang.fr:
        return fr;
    }
  }

  String get appName => "Klambocore";
  String get messaging => _t("Messagerie", "Messaging", "Mensagens");
  String get phoneLabel =>
      _t("Numéro de téléphone", "Phone number", "Número de telefone");
  String get phoneHint =>
      _t("844952966", "844952966", "844952966");
  String get countryCode =>
      _t("Indicatif", "Country code", "Indicativo");
  String get searchCountry => _t(
        "Rechercher un pays…",
        "Search a country…",
        "Pesquisar um país…",
      );
  String get phoneNationalInvalid => _t(
        "Saisissez un numéro valide (sans l'indicatif).",
        "Enter a valid number (without country code).",
        "Introduza um número válido (sem indicativo).",
      );
  String get otpLabel => _t("Code OTP", "OTP code", "Código OTP");
  String get continueLabel => _t("Continuer", "Continue", "Continuar");
  String get verify => _t("Vérifier", "Verify", "Verificar");
  String get changeNumber =>
      _t("Changer de numéro", "Change number", "Mudar de número");
  String get config => _t("Config", "Settings", "Configuração");
  String get language => _t("Langue", "Language", "Idioma");
  String get sourceTitle =>
      _t("Source serveur", "Server source", "Fonte do servidor");
  String get apiUrlLabel => _t("URL API", "API URL", "URL da API");
  String get apiUrlHint => "https://klambocore.com";
  String get apiUrlHelp => _t(
        "Sans slash final — ex. https://klambocore.com",
        "No trailing slash — e.g. https://klambocore.com",
        "Sem barra final — ex. https://klambocore.com",
      );
  String get saveSource =>
      _t("Enregistrer la source", "Save source", "Guardar fonte");
  String sourceSaved(String url) => _t(
        "Source enregistrée : $url",
        "Source saved: $url",
        "Fonte guardada: $url",
      );
  String get sourceRequired => _t(
        "Indique une URL source (ex. https://klambocore.com)",
        "Enter a source URL (e.g. https://klambocore.com)",
        "Indique um URL de origem (ex. https://klambocore.com)",
      );
  String get presetProd => _t("Prod", "Prod", "Prod");
  String get presetEmulator => _t("Émulateur", "Emulator", "Emulador");
  String get presetLocalhost => "Localhost";

  String get connectionFailed =>
      _t("Connexion échouée", "Connection failed", "Falha na ligação");
  String get connectionWeak => _t(
        "Connexion faible",
        "Weak connection",
        "Ligação fraca",
      );
  String get offlineCached => _t(
        "Hors ligne — contenu déjà chargé",
        "Offline — showing loaded content",
        "Offline — conteúdo já carregado",
      );
  String get syncWhenOnline => _t(
        "La synchronisation reprendra dès que la connexion sera rétablie.",
        "Sync will resume when the connection is restored.",
        "A sincronização retomará quando a ligação for restabelecida.",
      );
  String get networkError =>
      _t("Erreur réseau", "Network error", "Erro de rede");
  String get invalidResponse =>
      _t("Réponse invalide", "Invalid response", "Resposta inválida");
  String get apiError => _t("Erreur", "Error", "Erro");

  String otpSent(String phone, String channel) => _t(
        "Code envoyé vers $phone ($channel)",
        "Code sent to $phone ($channel)",
        "Código enviado para $phone ($channel)",
      );

  String get noOrg => _t(
        "Aucune organisation liée.",
        "No linked organization.",
        "Nenhuma organização associada.",
      );
  String get messagingDisabled => _t(
        "Messagerie désactivée pour vos organisations.",
        "Messaging is disabled for your organizations.",
        "Mensagens desativadas para as suas organizações.",
      );
  String get noConversations => _t(
        "Aucune conversation pour l’instant",
        "No conversations yet",
        "Ainda sem conversas",
      );
  String get selectConversation => _t(
        "Sélectionnez une conversation",
        "Select a conversation",
        "Selecione uma conversa",
      );
  String get noResults =>
      _t("Aucun résultat", "No results", "Sem resultados");
  String get writeMessage =>
      _t("Écrire un message", "Write a message", "Escrever mensagem");
  String get searchConversation => _t(
        "Rechercher une conversation…",
        "Search a conversation…",
        "Pesquisar uma conversa…",
      );
  String get refresh => _t("Actualiser", "Refresh", "Atualizar");
  String get logout => _t("Déconnexion", "Sign out", "Terminar sessão");
  String get logoutApp => _t("Logout", "Logout", "Logout");
  String get changeContact => _t(
        "Changer le contact",
        "Change contact",
        "Mudar o contacto",
      );
  String get changeContactHint => _t(
        "L’ancien numéro reste connecté tant qu’il n’est pas remplacé.",
        "The current number stays signed in until it is replaced.",
        "O número atual permanece ligado até ser substituído.",
      );
  String get changeContactSame => _t(
        "Ce numéro est déjà connecté.",
        "This number is already signed in.",
        "Este número já está ligado.",
      );
  String get changeContactCurrent => _t(
        "Numéro actuel",
        "Current number",
        "Número atual",
      );
  String get myAccount => _t("Mon compte", "My account", "A minha conta");
  String get profile => _t("Profil", "Profile", "Perfil");
  String get newMessage =>
      _t("Nouveau message", "New message", "Nova mensagem");
  String get userFallback =>
      _t("Utilisateur", "User", "Utilizador");
  String get callOneToOneOnly => _t(
        "Appel dispo uniquement en conversation 1:1.",
        "Calls are only available in 1:1 chats.",
        "Chamada disponível apenas em conversa 1:1.",
      );
  String get sendFailed => _t(
        "Envoi impossible — connexion faible",
        "Could not send — weak connection",
        "Envio impossível — ligação fraca",
      );

  String get enableAlertsTitle => _t(
        "Activer les alertes",
        "Enable alerts",
        "Ativar alertas",
      );
  String get enableAlertsBody => _t(
        "Autorise Klambo à t’envoyer des notifications pour les nouveaux messages et les appels entrants (son + badge).",
        "Allow Klambo to send notifications for new messages and incoming calls (sound + badge).",
        "Permite que o Klambo envie notificações de novas mensagens e chamadas (som + distintivo).",
      );
  String get allow => _t("Autoriser", "Allow", "Permitir");
  String get later => _t("Plus tard", "Later", "Mais tarde");
  String get alertsSettings =>
      _t("Alertes", "Alerts", "Alertas");
  String get appearance =>
      _t("Apparence", "Appearance", "Aparência");
  String get settings =>
      _t("Paramètres", "Settings", "Definições");
  String get themeTitle =>
      _t("Thème", "Theme", "Tema");
  String get wallpaperTitle =>
      _t("Fond d’écran", "Wallpaper", "Fundo");
  String get wallpaperHint => _t(
        "Motif en trait, même teinte que le fond",
        "Line pattern, same tone as the background",
        "Padrão em traço, o mesmo tom do fundo",
      );
  String get wallpaperPlain =>
      _t("Uni", "Plain", "Liso");
  String get wallpaperMessages =>
      _t("Messages", "Messages", "Mensagens");
  String get wallpaperAndroid =>
      _t("Android", "Android", "Android");
  String get wallpaperMix =>
      _t("Mixte", "Mixed", "Misto");
  String get notificationsSection =>
      _t("Notifications", "Notifications", "Notificações");
  String get notificationsSectionHint => _t(
        "Sons, messages et appels",
        "Sounds, messages and calls",
        "Sons, mensagens e chamadas",
      );
  String get systemNotificationSettings => _t(
        "Réglages système",
        "System settings",
        "Definições do sistema",
      );
  String get testMessageSound => _t(
        "Tester l’alerte message",
        "Test message alert",
        "Testar alerta de mensagem",
      );
  String get testMessageSoundHint => _t(
        "Joue le son système + bip Klambo",
        "Plays system sound + Klambo tone",
        "Toca o som do sistema + bip Klambo",
      );
  String get testMessageSoundDone => _t(
        "Alerte testée",
        "Alert tested",
        "Alerta testado",
      );
  String get appSection =>
      _t("Application", "Application", "Aplicação");
  String get logoutConfirm => _t(
        "Se déconnecter de Klambo ?",
        "Sign out of Klambo?",
        "Terminar sessão no Klambo?",
      );
  String get cancel => _t("Annuler", "Cancel", "Cancelar");
  String get themeLight => _t("Clair", "Light", "Claro");
  String get themeDark => _t("Sombre", "Dark", "Escuro");
  String get themeSystem =>
      _t("Système", "System", "Sistema");
  String get soundsEnabled =>
      _t("Sons", "Sounds", "Sons");
  String get messageAlerts =>
      _t("Notifications messages", "Message notifications", "Notificações de mensagens");
  String get callAlerts =>
      _t("Notifications appels", "Call notifications", "Notificações de chamadas");
  String get newMessageNotif =>
      _t("Nouveau message", "New message", "Nova mensagem");
  String get incomingAudioCall =>
      _t("Appel audio entrant", "Incoming voice call", "Chamada de voz a entrar");
  String get incomingVideoCall =>
      _t("Appel vidéo entrant", "Incoming video call", "Chamada de vídeo a entrar");

  String get online => _t("en ligne", "online", "online");
  String get offline => _t("hors ligne", "offline", "offline");
  String get lastSeenRecently => _t(
        "vu récemment",
        "last seen recently",
        "visto recentemente",
      );
  String lastSeenAt(String time) => _t(
        "vu à $time",
        "last seen at $time",
        "visto às $time",
      );
  String lastSeenOn(String day) => _t(
        "vu $day",
        "last seen $day",
        "visto $day",
      );
  String get yesterday => _t("hier", "yesterday", "ontem");

  String get videoCall =>
      _t("Appel vidéo", "Video call", "Chamada de vídeo");
  String get audioCall =>
      _t("Appel audio", "Voice call", "Chamada de voz");
  String get callSessionUnavailable => _t(
        "Session appel indisponible.",
        "Call session unavailable.",
        "Sessão de chamada indisponível.",
      );
  String callFailed(String error) => _t(
        "Appel impossible : $error",
        "Call failed: $error",
        "Chamada impossível: $error",
      );
  String get noMessagesYet => _t(
        "Aucun message — écrivez ci-dessous",
        "No messages yet — write below",
        "Sem mensagens — escreva abaixo",
      );
  String get writeMessageHint =>
      _t("Écrire un message…", "Write a message…", "Escrever mensagem…");

  String get chooseContact =>
      _t("Choisir un contact", "Choose a contact", "Escolher um contacto");
  String get searchContact => _t(
        "Rechercher un contact…",
        "Search a contact…",
        "Pesquisar um contacto…",
      );
  String get noContactsFound =>
      _t("Aucun contact trouvé", "No contacts found", "Nenhum contacto encontrado");
  String get firstMessageHint =>
      _t("Premier message…", "First message…", "Primeira mensagem…");
  String get writeFirstMessage => _t(
        "Écrivez un premier message.",
        "Write a first message.",
        "Escreva uma primeira mensagem.",
      );
  String get writeOrAttach => _t(
        "Écrivez un message ou joignez un fichier.",
        "Write a message or attach a file.",
        "Escreva uma mensagem ou anexe um ficheiro.",
      );
  String get conversationFallback =>
      _t("Conversation", "Conversation", "Conversa");
  String get organizationFallback =>
      _t("Organisation", "Organization", "Organização");
  String get myProfile => _t("Mon profil", "My profile", "O meu perfil");
  String get aboutApp => _t("À propos", "About", "Sobre");
  String get publisherLabel =>
      _t("Éditeur", "Publisher", "Editor");
  String get officialWebsite =>
      _t("Site officiel", "Official website", "Site oficial");
  String get verifiedPublisherHint => _t(
        "Application officielle Klambo publiée par Klambocore SARL.",
        "Official Klambo app published by Klambocore SARL.",
        "Aplicação oficial Klambo publicada por Klambocore SARL.",
      );
  String get changePhoto =>
      _t("Changer la photo", "Change photo", "Alterar foto");
  String get optional => _t("optionnel", "optional", "opcional");
  String get firstName => _t("Prénom", "First name", "Nome próprio");
  String get lastName => _t("Nom", "Last name", "Apelido");
  String get saveProfile =>
      _t("Enregistrer", "Save", "Guardar");
  String get contactInfo =>
      _t("Infos du contact", "Contact info", "Info do contacto");
  String get phoneNumber =>
      _t("Téléphone", "Phone", "Telefone");
  String get phoneUnavailable => _t(
        "Non renseigné",
        "Not available",
        "Não disponível",
      );
  String get phoneCopied => _t(
        "Numéro copié",
        "Phone number copied",
        "Número copiado",
      );
  String get copy => _t("Copier", "Copy", "Copiar");
  String get contactSection =>
      _t("Contact", "Contact", "Contacto");
  String get roleLabel => _t("Rôle", "Role", "Função");
  String get branchesLabel =>
      _t("Établissements", "Branches", "Estabelecimentos");
  String get branchLabel =>
      _t("Établissement", "Branch", "Estabelecimento");
  String get fullName =>
      _t("Nom complet", "Full name", "Nome completo");
  String get numberLabel => _t("Numéro", "Number", "Número");
  String get viewPhoto =>
      _t("Voir la photo", "View photo", "Ver a foto");
  String conversationArchived(int count) => count <= 1
      ? _t(
          "Conversation archivée",
          "Conversation archived",
          "Conversa arquivada",
        )
      : _t(
          "$count conversations archivées",
          "$count conversations archived",
          "$count conversas arquivadas",
        );
  String get selectOneConversation => _t(
        "Sélectionnez une seule conversation, puis ouvrez-la pour modifier un message.",
        "Select a single conversation, then open it to edit a message.",
        "Selecione uma única conversa e abra-a para editar uma mensagem.",
      );

  String get callRingingOut =>
      _t("Appel en cours", "Call in progress", "Chamada em curso");
  String get callPeerAway => _t("Appel", "Call", "Chamada");
  String get callRingingIn =>
      _t("Appel entrant", "Incoming call", "Chamada recebida");
  String get callConnecting =>
      _t("Connexion…", "Connecting…", "A ligar…");
  String get callBusy => _t("Occupé", "Busy", "Ocupado");
  String get callMediaLost =>
      _t("Connexion perdue", "Connection lost", "Ligação perdida");
  String get callPathDirect =>
      _t("Direct", "Direct", "Direto");
  String get callPathRelay => _t("Relais", "Relay", "Retransmissão");
  String get callIdentityFailed => _t(
        "Identité d'appel non vérifiée",
        "Call identity could not be verified",
        "Identidade da chamada não verificada",
      );
  String get callVideoActive =>
      _t("Visite vidéo", "Video visit", "Visita de vídeo");
  String get callAudioActive =>
      _t("Appel audio", "Voice call", "Chamada de voz");
  String get callEnded => _t("Terminé", "Ended", "Terminado");
  String get callPeerFallback =>
      _t("Correspondant", "Contact", "Contacto");
  String get callReject => _t("Refuser", "Decline", "Recusar");
  String get callAccept => _t("Accepter", "Accept", "Aceitar");
  String get callMute => _t("Muet", "Muted", "Mudo");
  String get callMic => _t("Micro", "Mic", "Micro");
  String get callSpeaker => _t("Haut-parleur", "Speaker", "Altifalante");
  String get callCamera => _t("Caméra", "Camera", "Câmara");
  String get callHangup => _t("Raccrocher", "Hang up", "Desligar");
  String get callMinimize => _t("Réduire", "Minimize", "Minimizar");
}

class LocaleController extends ChangeNotifier {
  LocaleController._();

  static final LocaleController instance = LocaleController._();

  static const _prefsKey = "klambo_app_lang";

  AppLang _lang = AppLang.fr;

  AppLang get lang => _lang;
  L10n get l10n => L10n(_lang);

  Future<void> loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    _lang = AppLang.fromCode(prefs.getString(_prefsKey));
    notifyListeners();
  }

  Future<void> setLang(AppLang lang) async {
    if (_lang == lang) return;
    _lang = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, lang.code);
    notifyListeners();
  }
}

final localeProvider = ChangeNotifierProvider<LocaleController>((ref) {
  return LocaleController.instance;
});

final l10nProvider = Provider<L10n>((ref) {
  return ref.watch(localeProvider).l10n;
});
