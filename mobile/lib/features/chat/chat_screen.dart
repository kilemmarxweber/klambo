import "dart:async";

import "package:audioplayers/audioplayers.dart";
import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/foundation.dart" show kIsWeb;
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:klambo_messagerie/core/app_page_route.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/core/call_trace.dart";
import "package:klambo_messagerie/core/data_saver_prefs.dart";
import "package:klambo_messagerie/core/format_time.dart";
import "package:klambo_messagerie/core/gallery_save.dart";
import "package:klambo_messagerie/core/l10n.dart";
import "package:klambo_messagerie/core/media_urls.dart";
import "package:klambo_messagerie/core/notify_trace.dart";
import "package:klambo_messagerie/core/person_name.dart";
import "package:klambo_messagerie/core/phone_number.dart";
import "package:klambo_messagerie/core/satisfaction_trace.dart";
import "package:klambo_messagerie/core/sound_service.dart";
import "package:klambo_messagerie/data/message_draft_store.dart";
import "package:klambo_messagerie/features/auth/session_provider.dart";
import "package:klambo_messagerie/features/calls/call_hub.dart";
import "package:klambo_messagerie/features/conversations/inbox_sync_policy.dart";
import "package:klambo_messagerie/features/chat/active_chat_provider.dart";
import "package:klambo_messagerie/features/chat/split_chat.dart";
import "package:klambo_messagerie/features/chat/contact_profile_screen.dart";
import "package:klambo_messagerie/features/conversations/group_profile_screen.dart";
import "package:klambo_messagerie/features/conversations/group_settings_screen.dart";
import "package:klambo_messagerie/features/parent/parent_hub_screen.dart";
import "package:klambo_messagerie/features/presence/presence_controller.dart";
import "package:klambo_messagerie/widgets/chat_composer.dart";
import "package:klambo_messagerie/widgets/chat_wallpaper.dart";
import "package:klambo_messagerie/widgets/connection_sync_bar.dart";
import "package:klambo_messagerie/widgets/eteyelo_messaging_app_bar.dart";
import "package:klambo_messagerie/widgets/linkified_text.dart";
import "package:klambo_messagerie/widgets/message_action_menu.dart";
import "package:klambo_messagerie/widgets/typing_dots.dart";
import "package:klambo_messagerie/widgets/user_avatar.dart";
import "package:uuid/uuid.dart";

const _kMessageDeletedLabel = "Ce message a été retiré";

enum MessageDeliveryStatus { pending, sent, read }

MessageDeliveryStatus messageDeliveryStatus(
  Map msg,
  DateTime? peerLastReadAt,
) {
  final id = msg["id"]?.toString() ?? "";
  if (id.startsWith("local-") || msg["pending"] == true) {
    return MessageDeliveryStatus.pending;
  }

  final apiStatus = msg["deliveryStatus"]?.toString().toUpperCase();
  if (apiStatus == "READ") return MessageDeliveryStatus.read;
  if (apiStatus == "SENT") {
    // L'API peut dire SENT alors qu'on a un watermark local plus récent.
  }

  final createdRaw = msg["createdAt"]?.toString();
  final created = createdRaw == null ? null : DateTime.tryParse(createdRaw);
  if (peerLastReadAt != null && created != null) {
    final createdUtc = created.toUtc();
    final readUtc = peerLastReadAt.toUtc();
    // Lu si le peer a ouvert le fil à l'instant du message ou après.
    if (!createdUtc.isAfter(readUtc)) {
      return MessageDeliveryStatus.read;
    }
  }
  if (apiStatus == "SENT") return MessageDeliveryStatus.sent;
  return MessageDeliveryStatus.sent;
}

/// Infère un watermark de lecture à partir des messages du peer (réponse = vu).
DateTime? inferPeerLastReadAt(List<dynamic> messages, String? myUserId) {
  if (myUserId == null || myUserId.isEmpty) return null;
  DateTime? latest;
  for (final raw in messages) {
    if (raw is! Map) continue;
    final senderId = raw["senderId"]?.toString();
    if (senderId == null || senderId == myUserId) continue;
    final created = DateTime.tryParse(raw["createdAt"]?.toString() ?? "");
    if (created == null) continue;
    final utc = created.toUtc();
    if (latest == null || utc.isAfter(latest)) latest = utc;
  }
  return latest;
}

DateTime? maxDateTime(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}

bool _messageIsDeleted(Map msg) => msg["deletedAt"] != null;

Map<String, dynamic>? _firstImageAttachment(Map msg) {
  final attachments = (msg["attachments"] as List?) ?? const [];
  for (final raw in attachments) {
    if (raw is! Map) continue;
    final att = Map<String, dynamic>.from(raw);
    if (_attachmentLooksLikeImage(att)) return att;
  }
  return null;
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.organizationId,
    required this.conversationId,
    required this.title,
    this.peerUserId,
    this.peerImage,
    this.memberImages = const [],
    this.peerTelephone,
    this.peerPrenom,
    this.peerNom,
    this.peerPostnom,
    this.peerRoleLabel,
    this.peerBranches = const [],
    this.noReply = false,
    this.conversationType,
    this.myRole,
    this.repliesLocked = false,
    this.embedded = false,
  });

  final String organizationId;
  final String conversationId;
  final String title;
  final String? peerUserId;
  final String? peerImage;
  final List<String> memberImages;
  final String? peerTelephone;
  final String? peerPrenom;
  final String? peerNom;
  final String? peerPostnom;
  final String? peerRoleLabel;
  final List<String> peerBranches;
  /// Bot notifications école — pas de champ de saisie / réponse.
  final bool noReply;
  final String? conversationType;
  final String? myRole;
  final bool repliesLocked;
  /// Affiché à côté de la liste (tablette / paysage), sans route propre.
  final bool embedded;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _composerKey = GlobalKey<ChatComposerState>();
  final _scroll = ScrollController();
  bool _stickToBottom = true;
  static const _nearBottomPx = 140.0;
  List<dynamic> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _fromCache = false;
  DateTime? _peerLastReadAt;
  String? _sendError;
  bool _calling = false;
  PresenceController? _presence;
  ProviderSubscription<AsyncValue<Map<String, dynamic>>>? _eventsSub;
  StateController<String?>? _activeConvCtrl;
  bool _typingPeer = false;
  Timer? _typingClear;
  DateTime? _typingSentAt;
  Timer? _presencePoll;
  Timer? _messagePoll;
  Timer? _threadRefresh;
  Timer? _draftSave;
  bool _messagesPrimed = false;
  final Set<String> _knownMessageIds = {};
  Map<String, dynamic>? _replyTo;
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  final Set<String> _starredIds = {};
  final Set<String> _pinnedIds = {};
  final Set<String> _noticeAckedIds = {};
  final Set<String> _noticeAckingIds = {};
  late bool _noReply = widget.noReply;
  late bool _repliesLocked = widget.repliesLocked;
  late String? _myRole = widget.myRole;
  late String? _conversationType = widget.conversationType;
  List<Map<String, dynamic>> _satisfactionPending = [];
  bool _satisfactionPromptOpen = false;
  bool _splitHandoff = false;

  bool get _isGroup => (_conversationType ?? "").toUpperCase() == "GROUP";
  bool get _isGroupAdmin => _myRole == "ADMIN";
  bool get _composerBlocked {
    if (_isNoReplyConversation) return true;
    if (_isGroup && _repliesLocked && !_isGroupAdmin) return true;
    return false;
  }

  bool get _isNoReplyConversation {
    if (_noReply || widget.noReply) return true;
    return widget.title.contains("· Notifications");
  }

  String get _headerTitle {
    if (_isGroup || _isNoReplyConversation) return widget.title;
    final label = displayPersonName(
      prenom: widget.peerPrenom,
      nom: widget.peerNom,
      postnom: widget.peerPostnom,
      name: widget.title,
    );
    return label.isEmpty ? widget.title : label;
  }

  String _messageSenderLabel(Map msg) {
    final sender = msg["sender"];
    final nested = sender is Map ? sender : null;
    final label = displayPersonName(
      prenom: msg["senderPrenom"]?.toString() ??
          nested?["prenom"]?.toString() ??
          (msg["senderId"]?.toString() == widget.peerUserId
              ? widget.peerPrenom
              : null),
      nom: msg["senderNom"]?.toString() ??
          nested?["nom"]?.toString() ??
          nested?["lastName"]?.toString(),
      postnom: msg["senderPostnom"]?.toString() ??
          nested?["postnom"]?.toString(),
      name: msg["senderName"]?.toString() ?? nested?["name"]?.toString(),
    );
    if (label.isNotEmpty) return label;
    if (!_isGroup) return _headerTitle;
    return "";
  }

  void _focusComposer() {
    _composerKey.currentState?.requestFocus();
  }

  void _selectMessageForReply(Map msg) {
    if (_composerBlocked || _selectionMode || _messageIsDeleted(msg)) return;
    setState(() => _replyTo = Map<String, dynamic>.from(msg));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusComposer());
  }

  bool _messageJustSent(Map msg, bool mine) {
    if (!mine) return false;
    if (msg["pending"] == true) return true;
    final created = DateTime.tryParse(msg["createdAt"]?.toString() ?? "");
    if (created == null) return false;
    return DateTime.now().difference(created) < const Duration(seconds: 1);
  }

  void _showCopiedSnackBar(String text) {
    if (text.trim().isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Message copié"),
        action: SnackBarAction(
          label: "Coller",
          onPressed: () {
            _composerKey.currentState?.pasteText(text);
          },
        ),
      ),
    );
    _focusComposer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _handOffToSplitPaneIfNeeded();
  }

  /// Si l'écran a été ouvert en plein écran puis que l'appareil passe
  /// en tablette ou en paysage, on rend le fil dans le panneau de droite.
  void _handOffToSplitPaneIfNeeded() {
    if (widget.embedded || _splitHandoff) return;
    if (!useSplitConversationLayout(context)) return;
    _splitHandoff = true;
    final target = SplitChatTarget(
      organizationId: widget.organizationId,
      conversationId: widget.conversationId,
      title: widget.title,
      peerUserId: widget.peerUserId,
      peerImage: widget.peerImage,
      memberImages: widget.memberImages,
      peerTelephone: widget.peerTelephone,
      peerPrenom: widget.peerPrenom,
      peerNom: widget.peerNom,
      peerPostnom: widget.peerPostnom,
      peerRoleLabel: widget.peerRoleLabel,
      peerBranches: widget.peerBranches,
      noReply: widget.noReply,
      conversationType: widget.conversationType,
      myRole: widget.myRole,
      repliesLocked: widget.repliesLocked,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!useSplitConversationLayout(context)) {
        _splitHandoff = false;
        return;
      }
      ref.read(splitChatProvider.notifier).state = target;
      Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScrollPosition);
    _input.addListener(_onInputChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activeConvCtrl = ref.read(activeConversationIdProvider.notifier);
      _activeConvCtrl!.state = widget.conversationId;
      unawaited(_restoreDraft());
      _load(silent: false);
      _bindPresence();
      _eventsSub = ref.listenManual(messagingEventsProvider, (_, next) {
        next.whenData(_onRealtimeEvent);
      });
      // Le fil est chargé une fois. Secours HTTP seulement si le socket tombe.
      _messagePoll = Timer.periodic(threadFallbackInterval, (_) {
        final up = ref.read(callHubProvider)?.socket.isConnected ?? false;
        if (!mounted || !shouldPollThread(socketConnected: up)) return;
        unawaited(_load(silent: true));
      });
    });
  }

  void _onScrollPosition() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    // Liste inversée : 0 = dernier message (bas de l’écran).
    _stickToBottom = pos.pixels <= _nearBottomPx;
  }

  void _scrollToBottom({required bool force, bool animated = false}) {
    void go() {
      if (!mounted || !_scroll.hasClients) return;
      if (!force && !_stickToBottom) return;
      // reverse:true → bas = offset 0
      if (animated) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(0);
      }
      _stickToBottom = true;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      go();
      // 2e passe après layout des bulles (évite d’ouvrir en haut).
      WidgetsBinding.instance.addPostFrameCallback((_) => go());
    });
  }

  void _onRealtimeEvent(Map<String, dynamic> event) {
    final type = event["type"]?.toString() ?? "";
    final payload = event["payload"];
    final convId = event["conversationId"]?.toString() ??
        (payload is Map ? payload["conversationId"]?.toString() : null);

    if (type == "typing") {
      if (convId != null && convId != widget.conversationId) return;
      final uid = event["userId"]?.toString();
      final me = ref.read(sessionProvider).me?["user"];
      final myId = me is Map ? me["id"]?.toString() : null;
      if (uid == null || uid == myId) return;
      setState(() => _typingPeer = true);
      _typingClear?.cancel();
      _typingClear = Timer(const Duration(seconds: 3), _clearPeerTyping);
      return;
    }

    if (type == "conversation.updated") {
      if (convId != null && convId != widget.conversationId) return;
      final reason = event["reason"]?.toString();
      final readAtRaw = event["lastReadAt"]?.toString();
      final readerId = event["userId"]?.toString();
      final me = ref.read(sessionProvider).me?["user"];
      final myId = me is Map ? me["id"]?.toString() : null;
      if (reason == "read" &&
          readAtRaw != null &&
          readerId != null &&
          readerId != myId) {
        final parsed = DateTime.tryParse(readAtRaw)?.toUtc();
        if (parsed != null) {
          setState(() {
            final current = _peerLastReadAt;
            if (current == null || parsed.isAfter(current)) {
              _peerLastReadAt = parsed;
            }
          });
        }
      }
      return;
    }

    if (type == "message.created" ||
        type == "message.updated" ||
        type == "message.deleted") {
      if (convId != null && convId != widget.conversationId) return;
      if (type == "message.created") {
        final senderId = event["senderId"]?.toString() ??
            (payload is Map ? payload["senderId"]?.toString() : null);
        final me = ref.read(sessionProvider).me?["user"];
        final myId = me is Map ? me["id"]?.toString() : null;
        if (senderId != null && senderId != myId) _clearPeerTyping();
        // Appliquer tout de suite (pas de refetch HTTP qui bloque le fil).
        _applyRealtimeCreated(event);
        return;
      }
      _threadRefresh?.cancel();
      _threadRefresh = Timer(const Duration(milliseconds: 400), () {
        if (mounted) unawaited(_load(silent: true));
      });
    }
  }

  /// Insère un message peer depuis le WS ; ignore l'écho de nos propres envois.
  void _applyRealtimeCreated(Map<String, dynamic> event) {
    final payload = event["payload"];
    final p = payload is Map
        ? Map<String, dynamic>.from(payload)
        : const <String, dynamic>{};
    final message = event["message"];
    final m = message is Map
        ? Map<String, dynamic>.from(message)
        : const <String, dynamic>{};

    final messageId = (event["messageId"] ??
            p["id"] ??
            p["messageId"] ??
            m["id"] ??
            event["id"])
        ?.toString();
    final senderId = (event["senderId"] ??
            p["senderId"] ??
            m["senderId"] ??
            (p["sender"] is Map ? (p["sender"] as Map)["id"] : null))
        ?.toString();
    final me = ref.read(sessionProvider).me?["user"];
    final myId = me is Map ? me["id"]?.toString() : null;

    // Écho de notre envoi : déjà confirmé via POST / bulle optimiste.
    if (senderId != null && myId != null && senderId == myId) {
      if (messageId != null && messageId.isNotEmpty) {
        _confirmOptimisticByServerId(messageId);
      }
      return;
    }

    if (messageId != null &&
        messageId.isNotEmpty &&
        _messages.any((msg) => msg["id"]?.toString() == messageId)) {
      return;
    }

    final body = (m["body"] ??
            p["body"] ??
            event["body"] ??
            event["bodyPreview"] ??
            p["bodyPreview"] ??
            p["text"] ??
            "")
        .toString();
    final senderName = (event["senderName"] ??
            p["senderName"] ??
            m["senderName"] ??
            (p["sender"] is Map ? (p["sender"] as Map)["name"] : null) ??
            "")
        .toString();
    final createdAt = (m["createdAt"] ??
            p["createdAt"] ??
            event["createdAt"] ??
            DateTime.now().toUtc().toIso8601String())
        .toString();
    final attachments = m["attachments"] ?? p["attachments"] ?? const [];

    if (!mounted) return;
    setState(() {
      _messages = [
        ..._messages,
        {
          "id": messageId ?? "rt-${const Uuid().v4()}",
          "senderId": senderId,
          "senderName": senderName,
          "body": body,
          "createdAt": createdAt,
          "pending": false,
          "attachments": attachments is List ? attachments : const [],
          if (m["replyTo"] != null) "replyTo": m["replyTo"],
          if (p["replyTo"] != null && m["replyTo"] == null)
            "replyTo": p["replyTo"],
        },
      ];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(force: false, animated: true);
    });
    // Pièces jointes / champs complets : rattrapage discret sans bloquer l'UI.
    if (attachments is! List || attachments.isEmpty) {
      _threadRefresh?.cancel();
      _threadRefresh = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) unawaited(_load(silent: true));
      });
    }
  }

  @override
  void dispose() {
    _eventsSub?.close();
    _input.removeListener(_onInputChanged);
    _typingClear?.cancel();
    _threadRefresh?.cancel();
    _draftSave?.cancel();
    _presencePoll?.cancel();
    _messagePoll?.cancel();
    _presence?.removeListener(_onPresenceChanged);
    final draftText = _input.text;
    final orgId = widget.organizationId;
    final convId = widget.conversationId;
    unawaited(
      MessageDraftStore.save(
        organizationId: orgId,
        conversationId: convId,
        text: draftText,
      ),
    );
    final activeConv = _activeConvCtrl;
    if (activeConv?.state == convId) {
      Future<void>(() {
        if (activeConv?.state == convId) activeConv?.state = null;
      });
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    final draft = await MessageDraftStore.load(
      organizationId: widget.organizationId,
      conversationId: widget.conversationId,
    );
    if (!mounted || draft == null || draft.isEmpty) return;
    if (_input.text.isNotEmpty) return;
    _input.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
  }

  Future<void> _persistDraftNow() async {
    await MessageDraftStore.save(
      organizationId: widget.organizationId,
      conversationId: widget.conversationId,
      text: _input.text,
    );
  }

  void _scheduleDraftSave() {
    _draftSave?.cancel();
    _draftSave = Timer(const Duration(milliseconds: 350), () {
      unawaited(_persistDraftNow());
    });
  }

  Future<void> _clearDraft() async {
    _draftSave?.cancel();
    await MessageDraftStore.clear(
      organizationId: widget.organizationId,
      conversationId: widget.conversationId,
    );
  }

  void _onPresenceChanged() {
    if (mounted) setState(() {});
  }

  void _clearPeerTyping() {
    _typingClear?.cancel();
    if (!mounted || !_typingPeer) return;
    setState(() => _typingPeer = false);
  }

  /// Signale à l'autre que l'on écrit, sans renvoyer à chaque frappe.
  void _onInputChanged() {
    _scheduleDraftSave();
    if (_input.text.trim().isEmpty) return;
    final now = DateTime.now();
    if (_typingSentAt != null &&
        now.difference(_typingSentAt!) < const Duration(seconds: 2)) {
      return;
    }
    _typingSentAt = now;
    ref.read(callHubProvider)?.socket.sendTyping(
          organizationId: widget.organizationId,
          conversationId: widget.conversationId,
        );
  }

  Future<void> _bindPresence() async {
    final peerId = widget.peerUserId;
    if (peerId == null) return;

    final hub = ref.read(callHubProvider);
    final presence = hub?.presence;
    if (hub == null || presence == null) return;

    _presence?.removeListener(_onPresenceChanged);
    _presence = presence;
    presence.addListener(_onPresenceChanged);
    hub.setActiveOrganization(widget.organizationId);
    await hub.refreshPeerPresence(
      organizationId: widget.organizationId,
      userId: peerId,
    );

    // Poll REST régulièrement : le WS Chrome échoue souvent.
    Future<void> pull() async {
      try {
        final repo = ref.read(messagingRepositoryProvider);
        final data = await repo.getPresence(
          widget.organizationId,
          userIds: [peerId],
        );
        final items = data["items"];
        if (items is List) presence.applyRestItems(items);
        debugPrint(
          "[presence] peer=$peerId items=$items",
        );
      } catch (e) {
        debugPrint("[presence] rest failed $e");
      }
    }

    await pull();
    _presencePoll?.cancel();
    _presencePoll = Timer.periodic(presenceFallbackInterval, (_) {
      final up = hub.socket.isConnected;
      if (!mounted || !shouldPollPresence(socketConnected: up)) return;
      pull();
    });
  }

  String? _presenceSubtitle(L10n l10n) {
    final peerId = widget.peerUserId;
    if (peerId == null) return null;
    final info = _presence?.of(peerId);
    if (info == null) return null;
    if (info.online) return l10n.online;

    final last = info.lastSeenAt;
    if (last == null) return l10n.offline;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(last.year, last.month, last.day);
    final diff = today.difference(day).inDays;

    if (diff == 0) return l10n.lastSeenAt(formatClock(last));
    if (diff == 1) return l10n.lastSeenOn(l10n.yesterday);
    if (now.difference(last).inHours < 24) return l10n.lastSeenRecently;
    return l10n.lastSeenOn(
      formatClockDay(last, yesterdayLabel: l10n.yesterday),
    );
  }

  void _openPeerProfile() {
    if (_isGroup) {
      Navigator.of(context).push(
        AppPageRoute(
          builder: (_) => GroupProfileScreen(
            name: _headerTitle,
            images: widget.memberImages,
            organizationId: widget.organizationId,
            conversationId: widget.conversationId,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => ContactProfileScreen(
          name: widget.title,
          prenom: widget.peerPrenom,
          image: widget.peerImage,
          telephone: widget.peerTelephone,
          roleLabel: widget.peerRoleLabel,
          branches: widget.peerBranches,
          userId: widget.peerUserId,
          organizationId: widget.organizationId,
        ),
      ),
    );
  }

  void _openSenderProfile(Map msg) {
    final senderId = msg["senderId"]?.toString();
    final peerId = widget.peerUserId;
    final isPeer = peerId != null && senderId == peerId;

    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => ContactProfileScreen(
          name: isPeer
              ? widget.title
              : (msg["senderName"]?.toString() ?? widget.title),
          prenom: isPeer
              ? widget.peerPrenom
              : msg["senderPrenom"]?.toString(),
          image: isPeer
              ? widget.peerImage
              : msg["senderImage"]?.toString(),
          telephone: isPeer
              ? (accountTelephone(msg) ??
                  widget.peerTelephone ??
                  extractPhoneNumber(msg) ??
                  findPhoneInText(widget.title) ??
                  msg["senderTelephone"]?.toString())
              : (accountTelephone(msg) ??
                  extractPhoneNumber(msg) ??
                  findPhoneInText(_messageSenderLabel(msg)) ??
                  msg["senderTelephone"]?.toString()),
          roleLabel: isPeer
              ? widget.peerRoleLabel
              : msg["senderRoleLabel"]?.toString(),
          branches: isPeer ? widget.peerBranches : const [],
          userId: senderId,
          organizationId: widget.organizationId,
        ),
      ),
    );
  }

  void _chimeNewChatMessages(List<Map<String, dynamic>> mapped, String? myId) {
    final fresh = <Map<String, dynamic>>[];
    final ids = <String>{};
    for (final msg in mapped) {
      final id = msg["id"]?.toString();
      if (id == null || id.isEmpty) continue;
      ids.add(id);
      if (!_messagesPrimed || _knownMessageIds.contains(id)) continue;
      final sender = msg["senderId"]?.toString() ??
          msg["authorId"]?.toString() ??
          (msg["sender"] is Map ? (msg["sender"] as Map)["id"]?.toString() : null);
      if (sender != null && sender == myId) {
        final created = msg["createdAt"]?.toString() ?? "";
        final ownBody = msg["body"]?.toString().trim() ?? "";
        final hub = ref.read(callHubProvider);
        hub?.rememberIncomingMessage(id);
        hub?.rememberIncomingMessage(
          "${widget.conversationId}|$created|${ownBody.isEmpty ? "Nouveau message" : ownBody}",
        );
        continue;
      }
      fresh.add(msg);
    }
    _knownMessageIds
      ..clear()
      ..addAll(ids);
    if (!_messagesPrimed) {
      _messagesPrimed = true;
      return;
    }
    if (fresh.isEmpty) return;
    final last = fresh.last;
    final id = last["id"]?.toString() ?? "";
    final bodyRaw = last["body"]?.toString().trim() ?? "";
    final body = bodyRaw.isEmpty ? "Nouveau message" : bodyRaw;
    final created = last["createdAt"]?.toString() ?? "";
    final altKey = "${widget.conversationId}|$created|$body";
    final dedupeKey = id.isNotEmpty ? id : altKey;
    unawaited(
      ref.read(callHubProvider)?.alertIncomingMessage(
            dedupeKey: dedupeKey,
            aliasKey: dedupeKey == altKey ? null : altKey,
            title: widget.title,
            body: body,
            avatarUrl: resolveImageUrl(
              last["senderImage"] ??
                  (last["sender"] is Map
                      ? (last["sender"] as Map)["image"]
                      : null) ??
                  widget.peerImage,
            ),
            conversationId: widget.conversationId,
            organizationId: widget.organizationId,
          ),
    );
  }

  Future<void> _load({bool silent = false}) async {
    // Pas de gros spinner plein écran : on garde le fond chat, refresh discret.
    try {
      final repo = ref.read(messagingRepositoryProvider);
      final data = await repo.listMessages(
        widget.organizationId,
        widget.conversationId,
      );
      final items = (data["items"] as List?) ?? [];
      final fromCache = data["fromCache"] == true;
      final mapped = items
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      final wasEmpty = _messages.isEmpty;
      final hasPeerReadKey = data.containsKey("peerLastReadAt");
      final peerReadRaw = data["peerLastReadAt"]?.toString();
      final apiPeerRead = !hasPeerReadKey
          ? null
          : (peerReadRaw == null || peerReadRaw.isEmpty
              ? null
              : DateTime.tryParse(peerReadRaw)?.toUtc());
      final me = ref.read(sessionProvider).me?["user"];
      final myId = me is Map ? me["id"]?.toString() : null;
      final inferred = inferPeerLastReadAt(mapped, myId);
      // Ne pas écraser les bulles encore en vol (envoi immédiat).
      final inflight = _messages
          .where((msg) {
            final id = msg["id"]?.toString() ?? "";
            return msg["pending"] == true ||
                msg["failed"] == true ||
                id.startsWith("local-");
          })
          .map((msg) => Map<String, dynamic>.from(msg as Map))
          .where((msg) {
            final sid = msg["id"]?.toString() ?? "";
            if (!sid.startsWith("local-") &&
                mapped.any((m) => m["id"]?.toString() == sid)) {
              return false;
            }
            return true;
          })
          .toList();
      setState(() {
        _messages = [...mapped, ...inflight];
        _loading = false;
        _fromCache = fromCache;
        _sendError = null;
        if (!fromCache && hasPeerReadKey) {
          // Max(API, inféré, actuel) — ne jamais régresser le watermark.
          _peerLastReadAt = maxDateTime(
            maxDateTime(apiPeerRead, inferred),
            _peerLastReadAt,
          );
        } else {
          _peerLastReadAt = maxDateTime(_peerLastReadAt, inferred);
        }
        if (data["noReply"] == true) _noReply = true;
        if (data.containsKey("repliesLocked")) {
          _repliesLocked = data["repliesLocked"] == true;
        }
        final role = data["myRole"]?.toString();
        if (role != null && role.isNotEmpty) _myRole = role;
        final ctype = data["conversationType"]?.toString();
        if (ctype != null && ctype.isNotEmpty) _conversationType = ctype;
      });
      if (!fromCache) {
        _chimeNewChatMessages(mapped, myId);
        unawaited(
          repo.conversationAction(
            widget.organizationId,
            widget.conversationId,
            "read",
          ),
        );
      }
      if (_isNoReplyConversation) {
        unawaited(_loadSatisfactionPending(openIfNeeded: true));
      }
      // Ouverture / premier contenu → bas immédiat (sans animation).
      // Refresh silencieux → bas seulement si déjà collé, jump discret.
      if (!silent || wasEmpty) {
        _scrollToBottom(force: true, animated: false);
      } else {
        _scrollToBottom(force: false, animated: false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _sendError = e.toString();
      });
    }
  }

  Future<void> _loadSatisfactionPending({bool openIfNeeded = false}) async {
    if (!_isNoReplyConversation) return;
    try {
      final data = await ref
          .read(messagingRepositoryProvider)
          .getSatisfactionPending(widget.organizationId);
      final pendingRaw = (data["pending"] as List?) ?? const [];
      final pending = pendingRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() => _satisfactionPending = pending);
      if (openIfNeeded && pending.isNotEmpty && !_satisfactionPromptOpen) {
        await _openSatisfactionWizard();
      }
    } catch (_) {
      // best effort: ne bloque pas le fil en cas d'erreur réseau.
    }
  }

  Future<void> _openSatisfactionWizard() async {
    if (_satisfactionPending.isEmpty) {
      await _loadSatisfactionPending(openIfNeeded: false);
    }
    if (!mounted || _satisfactionPromptOpen || _satisfactionPending.isEmpty) {
      return;
    }
    _satisfactionPromptOpen = true;
    var index = 0;
    var rating = 0;
    final commentCtrl = TextEditingController();
    String? error;
    bool sending = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final item = _satisfactionPending[index];
            final branch = item["branchName"]?.toString() ?? "Établissement";
            final children = ((item["children"] as List?) ?? const [])
                .map((e) => e?.toString() ?? "")
                .where((e) => e.isNotEmpty)
                .join(", ");
            return PopScope(
              canPop: false,
              child: AlertDialog(
                title: Text("Votre avis (${index + 1}/${_satisfactionPending.length})"),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(branch, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (children.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text("Enfants: $children", style: const TextStyle(fontSize: 12)),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      children: [
                        (1, "😡"),
                        (2, "😕"),
                        (3, "😐"),
                        (4, "😊"),
                        (5, "😍"),
                      ]
                          .map(
                            (entry) => ChoiceChip(
                              label: Text("${entry.$2} ${entry.$1}"),
                              selected: rating == entry.$1,
                              onSelected: (_) =>
                                  setLocalState(() => rating = entry.$1),
                            ),
                          )
                          .toList(),
                    ),
                    if (rating > 0 && rating <= 2) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: commentCtrl,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: "Expliquez en quelques mots",
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!, style: TextStyle(color: Colors.red.shade700)),
                    ],
                  ],
                ),
                actions: [
                  FilledButton(
                    onPressed: sending
                        ? null
                        : () async {
                            if (rating < 1 || rating > 5) {
                              setLocalState(() => error = "Choisissez une note.");
                              return;
                            }
                            final comment = commentCtrl.text.trim();
                            if (rating <= 2 && comment.length < 5) {
                              setLocalState(
                                () => error =
                                    "Ajoutez un commentaire (5 caractères minimum).",
                              );
                              return;
                            }
                            setLocalState(() {
                              error = null;
                              sending = true;
                            });
                            try {
                              await ref
                                  .read(messagingRepositoryProvider)
                                  .submitSatisfaction(
                                    widget.organizationId,
                                    branchId:
                                        item["branchId"]?.toString() ?? "",
                                    rating: rating,
                                    comment: rating <= 2 ? comment : null,
                                  );
                              await _loadSatisfactionPending(openIfNeeded: false);
                              if (!mounted) return;
                              final nextPending = _satisfactionPending;
                              if (nextPending.isEmpty) {
                                if (ctx.mounted) Navigator.of(ctx).pop();
                                return;
                              }
                              if (index >= nextPending.length) index = 0;
                              setLocalState(() {
                                rating = 0;
                                commentCtrl.clear();
                                error = null;
                                sending = false;
                              });
                            } catch (e) {
                              setLocalState(() {
                                error = e.toString();
                                sending = false;
                              });
                            }
                          },
                    child: Text(sending ? "Envoi..." : "Envoyer l'avis"),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    commentCtrl.dispose();
    _satisfactionPromptOpen = false;
  }

  Future<void> _editMessage(Map msg) async {
    final current = msg["body"]?.toString() ?? "";
    if (CallTraceInfo.tryParse(current) != null) return;
    final controller = TextEditingController(text: current);
    final newBody = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Modifier le message"),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: "Nouveau texte…",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Annuler"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newBody == null || newBody.isEmpty || newBody == current) return;
    final id = msg["id"]?.toString();
    if (id == null) return;
    try {
      await ref.read(messagingRepositoryProvider).editMessage(
            widget.organizationId,
            widget.conversationId,
            id,
            body: newBody,
          );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Modification impossible : $e")),
      );
    }
  }

  Future<void> _deleteMessage(Map msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Retirer le message"),
        content: const Text(
          "Le message sera retiré pour tout le monde. "
          "Une trace « Ce message a été retiré » restera visible.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Retirer"),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final id = msg["id"]?.toString();
    if (id == null) return;
    try {
      await ref.read(messagingRepositoryProvider).deleteMessage(
            widget.organizationId,
            widget.conversationId,
            id,
          );
      setState(() {
        _selectedIds.remove(id);
        // Optimistic : marque localement comme retiré.
        final idx = _messages.indexWhere((m) => m is Map && m["id"] == id);
        if (idx >= 0) {
          final copy = Map<String, dynamic>.from(_messages[idx] as Map);
          copy["deletedAt"] = DateTime.now().toIso8601String();
          copy["body"] = "";
          copy["attachments"] = [];
          copy["editedAt"] = null;
          _messages[idx] = copy;
        }
      });
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Suppression impossible : $e")),
      );
    }
  }

  Future<void> _acknowledgeNotice(String messageId) async {
    if (messageId.isEmpty ||
        messageId.startsWith("local-") ||
        _noticeAckedIds.contains(messageId) ||
        _noticeAckingIds.contains(messageId)) {
      return;
    }
    final l10n = ref.read(l10nProvider);
    setState(() => _noticeAckingIds.add(messageId));
    try {
      await ref.read(parentRepositoryProvider).acknowledgeNotice(
            organizationId: widget.organizationId,
            messageId: messageId,
          );
      if (!mounted) return;
      setState(() {
        _noticeAckingIds.remove(messageId);
        _noticeAckedIds.add(messageId);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _noticeAckingIds.remove(messageId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.noticeAckFailed)),
      );
    }
  }

  Future<void> _saveMessageImage(Map msg) async {
    final att = _firstImageAttachment(msg);
    if (att == null) return;
    final url = resolveImageUrl(att["url"]);
    final localRaw = att["localBytes"];
    Uint8List? local;
    if (localRaw is Uint8List) {
      local = localRaw;
    } else if (localRaw is List<int>) {
      local = Uint8List.fromList(localRaw);
    }
    final name = (att["fileName"] ?? att["filename"] ?? "klambo")
        .toString()
        .replaceAll(RegExp(r"\.[^.]+$"), "");

    try {
      await saveImageUrlToDeviceGallery(
        url: url,
        name: name,
        localBytes: local,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? "Image téléchargée"
                : "Image enregistrée dans la galerie",
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Enregistrement impossible : $e")),
      );
    }
  }

  Future<void> _deleteSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Retirer ${ids.length} message(s)"),
        content: const Text(
          "Les messages seront retirés pour tout le monde. "
          "Une trace restera visible.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Retirer"),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = ref.read(messagingRepositoryProvider);
    for (final id in ids) {
      try {
        await repo.deleteMessage(
          widget.organizationId,
          widget.conversationId,
          id,
        );
      } catch (_) {}
    }
    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
    });
    await _load(silent: true);
  }

  Future<void> _forwardMessage(Map msg) async {
    final body = msg["body"]?.toString() ?? "";
    if (body.isEmpty || CallTraceInfo.tryParse(body) != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ce message ne peut pas être transféré.")),
      );
      return;
    }
    final repo = ref.read(messagingRepositoryProvider);
    List<Map<String, dynamic>> items = [];
    try {
      final data = await repo.listConversations(widget.organizationId);
      items = ((data["items"] as List?) ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => e["id"]?.toString() != widget.conversationId)
          .toList();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Impossible de charger les conversations : $e")),
      );
      return;
    }
    if (!mounted) return;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Aucune autre conversation.")),
      );
      return;
    }
    final targetId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                "Transférer vers…",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.5,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[i];
                  final id = item["id"]?.toString() ?? "";
                  final title =
                      item["title"]?.toString() ?? "Conversation";
                  return ListTile(
                    leading: UserAvatar(name: title, radius: 20),
                    title: Text(title),
                    onTap: () => Navigator.pop(ctx, id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (targetId == null || targetId.isEmpty) return;
    try {
      await repo.sendMessage(
        widget.organizationId,
        targetId,
        body: body,
        clientMessageId: const Uuid().v4(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Message transféré")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Transfert impossible : $e")),
      );
    }
  }

  Future<void> _reactToMessage(Map msg, String emoji) async {
    if (emoji == "➕") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Choisissez une réaction rapide ci-dessus.")),
      );
      return;
    }
    final replyId = msg["id"]?.toString();
    try {
      await ref.read(messagingRepositoryProvider).sendMessage(
            widget.organizationId,
            widget.conversationId,
            body: emoji,
            replyToId: replyId,
            clientMessageId: const Uuid().v4(),
          );
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Réaction impossible : $e")),
      );
    }
  }

  Future<void> _onMessageLongPress(Map msg, bool mine) async {
    if (_selectionMode) {
      final id = msg["id"]?.toString();
      if (id == null) return;
      setState(() {
        if (_selectedIds.contains(id)) {
          _selectedIds.remove(id);
        } else {
          _selectedIds.add(id);
        }
        if (_selectedIds.isEmpty) _selectionMode = false;
      });
      return;
    }

    final body = msg["body"]?.toString() ?? "";
    final isDeleted = _messageIsDeleted(msg);
    final isCall = !isDeleted && CallTraceInfo.tryParse(body) != null;
    final hasImage = !isDeleted && _firstImageAttachment(msg) != null;
    final result = await showMessageActionMenu(
      context: context,
      mine: mine,
      canEdit: mine && !isCall && !isDeleted && body.trim().isNotEmpty,
      preview: isDeleted
          ? _kMessageDeletedLabel
          : (CallTraceInfo.tryParse(body)?.label ?? body),
      canSaveImage: hasImage,
      isDeleted: isDeleted,
      canReply: !_composerBlocked,
      canDelete: !isDeleted && (mine || _isGroupAdmin),
    );
    if (result == null || !mounted) return;

    switch (result.action) {
      case MessageMenuAction.react:
        if (isDeleted) return;
        await _reactToMessage(msg, result.emoji ?? "👍");
      case MessageMenuAction.reply:
        _selectMessageForReply(msg);
      case MessageMenuAction.copy:
        if (isDeleted) return;
        final text = CallTraceInfo.tryParse(body)?.label ?? body;
        await Clipboard.setData(ClipboardData(text: text));
        if (!mounted) return;
        _showCopiedSnackBar(text);
      case MessageMenuAction.forward:
        if (isDeleted) return;
        await _forwardMessage(msg);
      case MessageMenuAction.edit:
        if (isDeleted) return;
        await _editMessage(msg);
      case MessageMenuAction.pin:
        if (isDeleted) return;
        final id = msg["id"]?.toString();
        if (id == null) return;
        setState(() {
          if (_pinnedIds.contains(id)) {
            _pinnedIds.remove(id);
          } else {
            _pinnedIds.add(id);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _pinnedIds.contains(id)
                  ? "Message épinglé"
                  : "Message désépinglé",
            ),
          ),
        );
      case MessageMenuAction.star:
        if (isDeleted) return;
        final id = msg["id"]?.toString();
        if (id == null) return;
        setState(() {
          if (_starredIds.contains(id)) {
            _starredIds.remove(id);
          } else {
            _starredIds.add(id);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _starredIds.contains(id)
                  ? "Marqué comme important"
                  : "Marquage retiré",
            ),
          ),
        );
      case MessageMenuAction.select:
        final id = msg["id"]?.toString();
        if (id == null) return;
        setState(() {
          _selectionMode = true;
          _selectedIds
            ..clear()
            ..add(id);
        });
      case MessageMenuAction.saveImage:
        await _saveMessageImage(msg);
      case MessageMenuAction.delete:
        await _deleteMessage(msg);
    }
  }

  String _appendOptimisticText({
    required String body,
    required String? userId,
    String? replyToId,
    Map? replyTo,
    String? clientMessageId,
  }) {
    final cid = clientMessageId ?? const Uuid().v4();
    setState(() {
      _messages = [
        ..._messages,
        {
          "id": "local-$cid",
          "clientMessageId": cid,
          "senderId": userId,
          "senderName": "",
          "body": body,
          "createdAt": DateTime.now().toUtc().toIso8601String(),
          "pending": true,
          "attachments": const [],
          if (replyTo != null)
            "replyTo": {
              "id": replyToId,
              "senderName": replyTo["senderName"],
              "body": replyTo["body"],
            },
        },
      ];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(force: true, animated: true);
    });
    return cid;
  }

  String _appendOptimisticMedia({
    required String body,
    required PendingAttachment att,
    required String? userId,
    String? clientMessageId,
  }) {
    final cid = clientMessageId ?? const Uuid().v4();
    final attachment = <String, dynamic>{
      "id": "local-$cid",
      "kind": att.kind == PendingAttachmentKind.image
          ? "IMAGE"
          : att.kind == PendingAttachmentKind.audio
              ? "AUDIO"
              : "FILE",
      "url": null,
      "mimeType": att.mimeType,
      "fileName": att.filename,
      "durationMs": att.durationMs,
      "localBytes": att.bytes,
    };
    setState(() {
      _messages = [
        ..._messages,
        {
          "id": "local-$cid",
          "clientMessageId": cid,
          "senderId": userId,
          "senderName": "",
          "body": body,
          "createdAt": DateTime.now().toUtc().toIso8601String(),
          "pending": true,
          "attachments": [attachment],
        },
      ];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(force: true, animated: true);
    });
    return cid;
  }

  void _confirmOptimistic(String clientMessageId, String? serverId) {
    if (!mounted) return;
    setState(() {
      _messages = [
        for (final msg in _messages)
          if (msg["clientMessageId"]?.toString() == clientMessageId ||
              msg["id"]?.toString() == "local-$clientMessageId")
            {
              ...Map<String, dynamic>.from(msg as Map),
              "id": (serverId != null && serverId.isNotEmpty)
                  ? serverId
                  : msg["id"],
              "pending": false,
              "failed": false,
              "clientMessageId": clientMessageId,
            }
          else
            msg,
      ];
    });
  }

  void _confirmOptimisticByServerId(String serverId) {
    if (!mounted) return;
    final has = _messages.any((msg) => msg["id"]?.toString() == serverId);
    if (has) return;
    // Si un pending existe encore (course WS / POST), le rattacher.
    final pendingIdx = _messages.lastIndexWhere(
      (msg) =>
          msg["pending"] == true &&
          (msg["id"]?.toString() ?? "").startsWith("local-"),
    );
    if (pendingIdx < 0) return;
    setState(() {
      final copy = [..._messages];
      final msg = Map<String, dynamic>.from(copy[pendingIdx] as Map);
      msg["id"] = serverId;
      msg["pending"] = false;
      msg["failed"] = false;
      copy[pendingIdx] = msg;
      _messages = copy;
    });
  }

  void _failOptimistic(String clientMessageId) {
    if (!mounted) return;
    setState(() {
      _messages = [
        for (final msg in _messages)
          if (msg["clientMessageId"]?.toString() == clientMessageId ||
              msg["id"]?.toString() == "local-$clientMessageId")
            {
              ...Map<String, dynamic>.from(msg as Map),
              "pending": false,
              "failed": true,
            }
          else
            msg,
      ];
    });
  }

  Future<void> _send(
    String text,
    List<PendingAttachment> attachments,
  ) async {
    if (_composerBlocked) return;
    if (text.isEmpty && attachments.isEmpty) return;
    // Texte : envoi parallèle (realtime). Médias : un à la fois (upload).
    if (attachments.isNotEmpty && _sending) return;
    final l10n = ref.read(l10nProvider);
    final myId = ref.read(sessionProvider).me?["user"];
    final userId = myId is Map ? myId["id"]?.toString() : null;
    final repo = ref.read(messagingRepositoryProvider);
    final replySnapshot = _replyTo;
    final replyId = replySnapshot?["id"]?.toString();

    if (mounted) {
      setState(() {
        _sendError = null;
        _replyTo = null;
        if (attachments.isNotEmpty) _sending = true;
      });
    }
    unawaited(_clearDraft());

    try {
      if (attachments.isEmpty) {
        final clientId = const Uuid().v4();
        _appendOptimisticText(
          body: text,
          userId: userId,
          replyToId: replyId,
          replyTo: replySnapshot,
          clientMessageId: clientId,
        );
        // Ne bloque pas le composer : confirmation en arrière-plan.
        unawaited(() async {
          try {
            final res = await repo.sendMessage(
              widget.organizationId,
              widget.conversationId,
              body: text,
              replyToId: replyId,
              clientMessageId: clientId,
            );
            _confirmOptimistic(
              clientId,
              res["messageId"]?.toString() ?? res["id"]?.toString(),
            );
          } catch (_) {
            _failOptimistic(clientId);
            if (mounted) setState(() => _sendError = l10n.sendFailed);
          }
        }());
        return;
      }

      var captionUsed = false;
      for (var i = 0; i < attachments.length; i++) {
        final att = attachments[i];
        final caption = (!captionUsed && text.isNotEmpty) ? text : "";
        if (caption.isNotEmpty) captionUsed = true;
        final clientId = const Uuid().v4();
        _appendOptimisticMedia(
          body: caption.isNotEmpty
              ? caption
              : att.kind == PendingAttachmentKind.image
                  ? "[image]"
                  : att.kind == PendingAttachmentKind.audio
                      ? "[audio]"
                      : "[file]",
          att: att,
          userId: userId,
          clientMessageId: clientId,
        );
        try {
          final res = await repo.sendMediaMessage(
            widget.organizationId,
            widget.conversationId,
            bytes: att.bytes,
            filename: att.filename,
            mimeType: att.mimeType,
            body: caption,
            clientMessageId: clientId,
            durationMs: att.durationMs,
          );
          _confirmOptimistic(
            clientId,
            res["messageId"]?.toString() ?? res["id"]?.toString(),
          );
        } catch (e) {
          _failOptimistic(clientId);
          rethrow;
        }
      }
      if (text.isNotEmpty && !captionUsed) {
        final clientId = const Uuid().v4();
        _appendOptimisticText(
          body: text,
          userId: userId,
          replyToId: replyId,
          replyTo: replySnapshot,
          clientMessageId: clientId,
        );
        try {
          final res = await repo.sendMessage(
            widget.organizationId,
            widget.conversationId,
            body: text,
            replyToId: replyId,
            clientMessageId: clientId,
          );
          _confirmOptimistic(
            clientId,
            res["messageId"]?.toString() ?? res["id"]?.toString(),
          );
        } catch (e) {
          _failOptimistic(clientId);
          rethrow;
        }
      }
    } catch (e) {
      if (mounted) setState(() => _sendError = l10n.sendFailed);
    } finally {
      if (mounted && attachments.isNotEmpty) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _startCall({String kind = "AUDIO"}) async {
    if (_calling) return;
    final peerId = widget.peerUserId;
    final hub = ref.read(callHubProvider);
    final l10n = ref.read(l10nProvider);
    if (peerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.callOneToOneOnly)),
      );
      return;
    }
    if (hub == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.callSessionUnavailable)),
      );
      return;
    }
    setState(() => _calling = true);
    try {
      final me = ref.read(sessionProvider).me?["user"];
      final callerName = me is Map ? me["name"]?.toString() : null;
      await hub.startOutgoing(
        organizationId: widget.organizationId,
        calleeId: peerId,
        kind: kind,
        conversationId: widget.conversationId,
        peerName: widget.title,
        callerName: callerName,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.callFailed("$e"))),
        );
      }
    } finally {
      if (mounted) setState(() => _calling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(callHubProvider);
    final l10n = ref.watch(l10nProvider);
    final myId = ref.watch(sessionProvider).me?["user"];
    final userId = myId is Map ? myId["id"]?.toString() : null;
    final canCall = widget.peerUserId != null && !_isNoReplyConversation;
    final subtitle = _isNoReplyConversation
        ? "Notifications — sans réponse"
        : (_typingPeer ? "écrit…" : _presenceSubtitle(l10n));

    return Scaffold(
      appBar: _selectionMode
          ? AppBar(
              backgroundColor: EteyeloColors.primaryDarker,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selectionMode = false;
                  _selectedIds.clear();
                }),
              ),
              title: Text("${_selectedIds.length} sélectionné(s)"),
              actions: [
                IconButton(
                  tooltip: "Copier",
                  onPressed: () async {
                    final texts = _messages
                        .whereType<Map>()
                        .where(
                          (m) => _selectedIds.contains(m["id"]?.toString()),
                        )
                        .map((m) {
                      final b = m["body"]?.toString() ?? "";
                      return CallTraceInfo.tryParse(b)?.label ?? b;
                    }).where((t) => t.trim().isNotEmpty);
                    final joined = texts.join("\n");
                    await Clipboard.setData(ClipboardData(text: joined));
                    if (!mounted) return;
                    setState(() {
                      _selectionMode = false;
                      _selectedIds.clear();
                    });
                    _showCopiedSnackBar(joined);
                  },
                  icon: const Icon(Icons.copy_rounded),
                ),
                IconButton(
                  tooltip: "Supprimer",
                  onPressed: _deleteSelected,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            )
          : EteyeloChatAppBar(
        title: _headerTitle,
        subtitle: subtitle,
        peerImage: widget.peerImage,
        groupPhotos: _isGroup ? widget.memberImages : null,
        peerName: _headerTitle,
        showBack: !widget.embedded,
        onProfileTap: _openPeerProfile,
        actions: [
          if (canCall)
            IconButton(
              tooltip: l10n.videoCall,
              onPressed: _calling ? null : () => _startCall(kind: "VIDEO"),
              icon: const Icon(Icons.videocam_outlined),
            ),
          if (canCall)
            IconButton(
              tooltip: l10n.audioCall,
              onPressed: _calling ? null : () => _startCall(kind: "AUDIO"),
              icon: const Icon(Icons.call),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (_) => [
              PopupMenuItem(value: "refresh", child: Text(l10n.refresh)),
              if (_isGroup)
                const PopupMenuItem(
                  value: "group",
                  child: Text("Paramètres du groupe"),
                ),
            ],
            onSelected: (v) {
              if (v == "refresh") {
                _load();
                _bindPresence();
              } else if (v == "group") {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupSettingsScreen(
                      organizationId: widget.organizationId,
                      conversationId: widget.conversationId,
                      title: widget.title,
                    ),
                  ),
                ).then((_) {
                  if (mounted) _load(silent: true);
                });
              }
            },
          ),
        ],
      ),
      backgroundColor: ChatWallpaper.baseFor(context),
      body: Column(
        children: [
          if (_fromCache && _messages.isNotEmpty) const ConnectionSyncBar(),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ChatWallpaper(),
                Column(
                  children: [
                    Expanded(
                      child: _messages.isEmpty
                ? Center(
                    child: _loading
                        ? const SizedBox.shrink()
                        : Text(
                            l10n.noMessagesYet,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      // reverse:true → index 0 = dernier message (bas).
                      final realIndex = _messages.length - 1 - index;
                      final msg = _messages[realIndex] as Map;
                      final mine = msg["senderId"]?.toString() == userId;
                      final older = realIndex > 0
                          ? _messages[realIndex - 1] as Map
                          : null;
                      final newer = realIndex < _messages.length - 1
                          ? _messages[realIndex + 1] as Map
                          : null;
                      final sameAsOlder = older != null &&
                          older["senderId"]?.toString() ==
                              msg["senderId"]?.toString();
                      final sameAsNewer = newer != null &&
                          newer["senderId"]?.toString() ==
                              msg["senderId"]?.toString();
                      final attachments =
                          (msg["attachments"] as List?) ?? const [];

                      final edited = msg["editedAt"] != null;
                      final deleted = _messageIsDeleted(msg);
                      final body = deleted
                          ? _kMessageDeletedLabel
                          : (msg["body"]?.toString() ?? "");
                      final msgId = msg["id"]?.toString() ?? "";
                      final selected = _selectedIds.contains(msgId);
                      final satisfactionTrace =
                          deleted ? null : SatisfactionTrace.tryParse(body);
                      if (satisfactionTrace != null) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320),
                              child: Card(
                                elevation: 0,
                                color: const Color(0xFFEFF6FF),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        satisfactionTrace.preview,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1E3A8A),
                                        ),
                                      ),
                                      if (satisfactionTrace.label.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          satisfactionTrace.label,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF334155),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      FilledButton(
                                        onPressed: satisfactionTrace.pendingCount >
                                                0
                                            ? _openSatisfactionWizard
                                            : null,
                                        child: Text(
                                          satisfactionTrace.pendingCount > 0
                                              ? "Donner mon avis"
                                              : "Avis déjà envoyé",
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      final notifyTrace =
                          deleted ? null : NotifyTrace.tryParse(body);
                      if (notifyTrace != null) {
                        final showAck = !mine &&
                            msgId.isNotEmpty &&
                            !msgId.startsWith("local-") &&
                            notifyTrace.suggestsOfficialAck;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: GestureDetector(
                              onLongPress: () =>
                                  _onMessageLongPress(msg, mine),
                              onTap: _selectionMode
                                  ? () => _onMessageLongPress(msg, mine)
                                  : null,
                              child: NotifyMessageCard(
                                trace: notifyTrace,
                                showReadAck: showAck,
                                acked: _noticeAckedIds.contains(msgId),
                                acking: _noticeAckingIds.contains(msgId),
                                ackLabel: l10n.noticeAckRead,
                                ackedLabel: l10n.noticeAckDone,
                                onAck: () => _acknowledgeNotice(msgId),
                              ),
                            ),
                          ),
                        );
                      }
                      final callTrace =
                          deleted ? null : CallTraceInfo.tryParse(body);
                      final replyTo = msg["replyTo"];
                      final replyDeleted = replyTo is Map &&
                          replyTo["deletedAt"] != null;
                      return _SwipeToReply(
                        enabled: !deleted &&
                            !_selectionMode &&
                            !_composerBlocked &&
                            msgId.isNotEmpty,
                        onReply: () => _selectMessageForReply(msg),
                        child: Padding(
                        padding: EdgeInsets.only(
                          top: sameAsNewer ? 1 : 5,
                          bottom: sameAsOlder ? 0 : 2,
                        ),
                        child: GestureDetector(
                          onLongPress: () =>
                              _onMessageLongPress(msg, mine),
                          onTap: _selectionMode
                              ? () => _onMessageLongPress(msg, mine)
                              : (callTrace != null
                                  ? () => _startCall(
                                        kind: callTrace.isVideo
                                            ? "VIDEO"
                                            : "AUDIO",
                                      )
                                  : null),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (_selectionMode) ...[
                                Padding(
                                  padding: const EdgeInsets.only(
                                    right: 8,
                                    bottom: 4,
                                  ),
                                  child: Icon(
                                    selected
                                        ? Icons.check_circle
                                        : Icons.circle_outlined,
                                    color: selected
                                        ? EteyeloColors.primary
                                        : Colors.grey,
                                    size: 20,
                                  ),
                                ),
                              ],
                              Expanded(
                                child: _MessageBubble(
                                  body: body,
                                  time: formatMessageTime(
                                    msg["createdAt"]?.toString(),
                                  ),
                                  mine: mine,
                                  deliveryStatus: mine
                                      ? messageDeliveryStatus(
                                          msg,
                                          _peerLastReadAt,
                                        )
                                      : null,
                                  edited: edited && !deleted,
                                  deleted: deleted,
                                  starred: !deleted &&
                                      _starredIds.contains(msgId),
                                  pinned: !deleted &&
                                      _pinnedIds.contains(msgId),
                                  appearing: _messageJustSent(msg, mine),
                                  replySender: replyTo is Map
                                      ? _messageSenderLabel({
                                          "senderName": replyTo["senderName"],
                                          "senderPrenom": replyTo["senderPrenom"],
                                          "senderNom": replyTo["senderNom"],
                                        })
                                      : null,
                                  replyBody: replyTo is Map
                                      ? (replyDeleted
                                          ? _kMessageDeletedLabel
                                          : replyTo["body"]?.toString())
                                      : null,
                                  senderName: _messageSenderLabel(msg),
                                  senderImage:
                                      msg["senderImage"]?.toString(),
                                  showAvatar: !mine &&
                                      !sameAsNewer &&
                                      (!_isGroup ||
                                          resolveImageUrl(
                                                msg["senderImage"]
                                                    ?.toString(),
                                              ) !=
                                              null),
                                  showSenderName: !mine && !sameAsOlder,
                                  clusterTop: !sameAsOlder,
                                  clusterBottom: !sameAsNewer,
                                  attachments:
                                      deleted || callTrace != null
                                          ? const []
                                          : attachments,
                                  call: callTrace,
                                  showMenuButton: !_selectionMode,
                                  onMenuTap: () =>
                                      _onMessageLongPress(msg, mine),
                                  onAvatarTap: !mine
                                      ? () => _openSenderProfile(msg)
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ),
                      );
                    },
                  ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      alignment: Alignment.bottomLeft,
                      child: _typingPeer
                          ? const TypingBubble()
                          : const SizedBox(
                              width: double.infinity,
                              height: 0,
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_sendError != null)
            Material(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  _sendError!,
                  style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                ),
              ),
            ),
          if (_replyTo != null && !_composerBlocked)
            Material(
              color: Colors.white,
              elevation: 1,
              child: ListTile(
                dense: true,
                leading: const Icon(
                  Icons.reply_rounded,
                  color: EteyeloColors.primaryDark,
                ),
                title: Text(
                  "Réponse à ${_messageSenderLabel(_replyTo!)}",
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: EteyeloColors.primaryDark,
                  ),
                ),
                subtitle: Text(
                  (_replyTo!["body"]?.toString() ?? "").trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => setState(() => _replyTo = null),
                ),
              ),
            ),
          if (_composerBlocked)
            Material(
              color: const Color(0xFFF1F5F9),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      _isNoReplyConversation
                          ? Icons.notifications_none_rounded
                          : Icons.lock_outline,
                      size: 20,
                      color: Colors.blueGrey.shade600,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isNoReplyConversation
                            ? (_satisfactionPending.isNotEmpty
                                ? "Avis mensuel requis — ${_satisfactionPending.length} établissement(s) en attente"
                                : "Notifications automatiques — réponses désactivées")
                            : "Réponses verrouillées par un admin du groupe",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.blueGrey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ChatComposer(
              key: _composerKey,
              controller: _input,
              sending: _sending,
              onSend: _send,
            ),
        ],
      ),
    );
  }
}

/// Carte d'appel dans la bulle : icône, titre, sous-titre.
class _CallMessageCard extends StatelessWidget {
  const _CallMessageCard({required this.info, required this.textColor});

  final CallTraceInfo info;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final missed = info.isMissedLike;
    final accent = missed ? const Color(0xFFE53935) : const Color(0xFF1FA855);
    final icon = info.isVideo
        ? (missed ? Icons.videocam_off_rounded : Icons.videocam_rounded)
        : (missed ? Icons.call_end_rounded : Icons.call_rounded);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            child: SizedBox(
              width: 38,
              height: 38,
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  info.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.2,
                    color: EteyeloColors.bubbleMeta,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton menu discret avec léger scale au tap.
class _MessageMenuButton extends StatefulWidget {
  const _MessageMenuButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_MessageMenuButton> createState() => _MessageMenuButtonState();
}

class _MessageMenuButtonState extends State<_MessageMenuButton> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.86),
      onTapUp: (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: const Padding(
          padding: EdgeInsets.all(2),
          child: Icon(
            Icons.expand_more_rounded,
            size: 18,
            color: Color(0xFF8696A0),
          ),
        ),
      ),
    );
  }
}

/// Pointe (« tête ») style WhatsApp sous l’angle de la bulle.
class _BubbleTailPainter extends CustomPainter {
  _BubbleTailPainter({required this.color, required this.mine});

  final Color color;
  final bool mine;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    if (mine) {
      path.moveTo(0, 0);
      path.quadraticBezierTo(size.width * 0.15, size.height * 0.35, size.width, size.height);
      path.quadraticBezierTo(size.width * 0.2, size.height * 0.85, 0, size.height * 0.55);
    } else {
      path.moveTo(size.width, 0);
      path.quadraticBezierTo(
        size.width * 0.85,
        size.height * 0.35,
        0,
        size.height,
      );
      path.quadraticBezierTo(
        size.width * 0.8,
        size.height * 0.85,
        size.width,
        size.height * 0.55,
      );
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.mine != mine;
}

/// Ticks de livraison : horloge → ✓ envoyé → ✓✓ lu.
class _DeliveryTicks extends StatelessWidget {
  const _DeliveryTicks({required this.status});

  final MessageDeliveryStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageDeliveryStatus.pending:
        return Icon(
          Icons.access_time_rounded,
          size: 12,
          color: EteyeloColors.bubbleMeta.withValues(alpha: 0.85),
        );
      case MessageDeliveryStatus.sent:
        return Icon(
          Icons.done_rounded,
          size: 14,
          color: EteyeloColors.bubbleMeta.withValues(alpha: 0.9),
        );
      case MessageDeliveryStatus.read:
        return Icon(
          Icons.done_all_rounded,
          size: 14,
          color: EteyeloColors.primary.withValues(alpha: 0.9),
        );
    }
  }
}

/// Glisser le message vers la gauche pour le préparer en réponse.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({
    required this.enabled,
    required this.onReply,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onReply;
  final Widget child;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  static const _limit = 72.0;
  static const _trigger = 48.0;

  double _drag = 0;
  late final AnimationController _controller;
  Animation<double>? _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() {
        final anim = _anim;
        if (anim == null) return;
        setState(() => _drag = anim.value);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _settle({required bool reply}) {
    final from = _drag;
    _anim = Tween<double>(begin: from, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller
      ..value = 0
      ..forward();
    if (reply) widget.onReply();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final progress = (-_drag / _limit).clamp(0.0, 1.0);
    return GestureDetector(
      onHorizontalDragStart: (_) => _controller.stop(),
      onHorizontalDragUpdate: (details) {
        setState(() {
          _drag = (_drag + details.delta.dx).clamp(-_limit, 0);
        });
      },
      onHorizontalDragEnd: (details) {
        final flung = (details.primaryVelocity ?? 0) < -700;
        _settle(reply: _drag <= -_trigger || flung);
      },
      onHorizontalDragCancel: () => _settle(reply: false),
      child: Stack(
        alignment: Alignment.centerRight,
        clipBehavior: Clip.none,
        children: [
          Opacity(
            opacity: progress,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.reply_rounded,
                color: EteyeloColors.primary.withValues(
                  alpha: 0.35 + 0.65 * progress,
                ),
                size: 22,
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_drag, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// Apparition d'un message à l'envoi : glisse, grandit, puis se pose.
class _SendArrival extends StatefulWidget {
  const _SendArrival({
    required this.animate,
    required this.fromRight,
    required this.child,
  });

  final bool animate;
  final bool fromRight;
  final Widget child;

  @override
  State<_SendArrival> createState() => _SendArrivalState();
}

class _SendArrivalState extends State<_SendArrival>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _SendArrival oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.animate) {
      _controller.value = 1;
    } else if (!oldWidget.animate) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final raw = _controller.value;
        final t = Curves.easeOutCubic.transform(raw.clamp(0.0, 1.0));
        final slide = (1 - t) * (widget.fromRight ? 16.0 : -12.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(slide, (1 - t) * 6),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Bulle responsive : largeur selon le contenu, forme WhatsApp.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.body,
    required this.time,
    required this.mine,
    required this.edited,
    required this.senderName,
    required this.senderImage,
    required this.showAvatar,
    required this.showSenderName,
    required this.clusterTop,
    required this.clusterBottom,
    required this.attachments,
    this.deliveryStatus,
    this.deleted = false,
    this.starred = false,
    this.pinned = false,
    this.replySender,
    this.replyBody,
    this.appearing = false,
    this.showMenuButton = true,
    this.onMenuTap,
    this.onAvatarTap,
    this.call,
  });

  final String body;
  final String time;
  final bool mine;
  final MessageDeliveryStatus? deliveryStatus;
  final bool edited;
  final bool deleted;
  final bool starred;
  final bool pinned;
  final String? replySender;
  final String? replyBody;
  final bool appearing;
  final String senderName;
  final String? senderImage;
  final bool showAvatar;
  final bool showSenderName;
  final bool clusterTop;
  final bool clusterBottom;
  final List attachments;
  final bool showMenuButton;
  final VoidCallback? onMenuTap;
  final VoidCallback? onAvatarTap;
  final CallTraceInfo? call;

  bool get _isPlaceholderBody {
    final t = body.trim().toLowerCase();
    return t.isEmpty ||
        t == "[image]" ||
        t == "[audio]" ||
        t == "[file]" ||
        t == "[video]";
  }

  /// Largeur figée dès le premier frame, d’après le texte (pas de mesure
  /// après coup qui ferait sauter la carte).
  double _recommendedWidth(double maxW) {
    const hPad = 18.0;
    final maxInner = (maxW - hPad).clamp(48.0, maxW);
    var inner = 0.0;

    void grow(double w) {
      if (w > inner) inner = w;
    }

    double lineWidth(String text, double perChar) {
      var longest = 0;
      for (final line in text.split("\n")) {
        if (line.length > longest) longest = line.length;
      }
      final raw = longest * perChar;
      return raw > maxInner ? maxInner : raw;
    }

    if (call != null) {
      grow(228);
    } else if (!_isPlaceholderBody || attachments.isEmpty) {
      grow(lineWidth(body, 9.0));
    }
    if (showSenderName && senderName.isNotEmpty) {
      grow(lineWidth(senderName, 7.6));
    }
    final quoted = replyBody?.trim() ?? "";
    if (quoted.isNotEmpty) {
      grow(lineWidth(replySender?.trim().isNotEmpty == true ? replySender! : "Message", 7.4) + 14);
      grow(lineWidth(quoted, 7.0) + 14);
    }
    if (attachments.isNotEmpty) {
      final hasImage = attachments.any(
        (raw) =>
            raw is Map &&
            _attachmentLooksLikeImage(Map<String, dynamic>.from(raw)),
      );
      if (hasImage) {
        grow((maxW - 24).clamp(160.0, 280.0));
      } else {
        grow(176);
      }
    }
    grow(mine ? 78 : 54);

    final width = inner + hPad;
    if (width > maxW) return maxW;
    if (width < 78) return 78;
    return width;
  }

  BorderRadius get _radius {
    const soft = 18.0;
    const tip = 4.0;
    // Coin « tête » : plus pointu en bas côté destinataire/expéditeur.
    if (mine) {
      return BorderRadius.only(
        topLeft: const Radius.circular(soft),
        topRight: Radius.circular(clusterTop ? soft : 10),
        bottomLeft: const Radius.circular(soft),
        bottomRight: Radius.circular(clusterBottom ? tip : soft),
      );
    }
    return BorderRadius.only(
      topLeft: Radius.circular(clusterTop ? soft : 10),
      topRight: const Radius.circular(soft),
      bottomLeft: Radius.circular(clusterBottom ? tip : soft),
      bottomRight: const Radius.circular(soft),
    );
  }

  Widget _metaRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (edited) ...[
          Text(
            "modifié",
            style: TextStyle(
              fontSize: 10,
              fontStyle: FontStyle.italic,
              color: EteyeloColors.bubbleMeta.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(width: 4),
        ],
        if (pinned) ...[
          Icon(
            Icons.push_pin,
            size: 11,
            color: EteyeloColors.bubbleMeta.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 3),
        ],
        if (starred) ...[
          Icon(
            Icons.star_rounded,
            size: 12,
            color: Colors.amber.shade700,
          ),
          const SizedBox(width: 3),
        ],
        Text(
          time,
          style: const TextStyle(
            fontSize: 10.5,
            height: 1,
            letterSpacing: 0.1,
            color: EteyeloColors.bubbleMeta,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (mine) ...[
          const SizedBox(width: 3),
          _DeliveryTicks(status: deliveryStatus ?? MessageDeliveryStatus.sent),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.sizeOf(context).width;
    final reserved = (mine ? 36.0 : 70.0) + (showMenuButton ? 30.0 : 0);
    final maxW = (screenW - reserved).clamp(140.0, screenW * 0.78);
    final bubbleW = _recommendedWidth(maxW);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = mine
        ? (dark
            ? EteyeloColors.bubbleOutgoingDark
            : EteyeloColors.bubbleOutgoing)
        : (dark
            ? EteyeloColors.bubbleIncomingDark
            : EteyeloColors.bubbleIncoming);
    final textColor = mine
        ? (dark
            ? EteyeloColors.bubbleOutgoingTextDark
            : EteyeloColors.bubbleOutgoingText)
        : (dark
            ? EteyeloColors.bubbleIncomingTextDark
            : EteyeloColors.bubbleIncomingText);

    final showTail = clusterBottom;

    final bubbleBody = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          if (showSenderName && senderName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: GestureDetector(
                onTap: onAvatarTap,
                child: Text(
                  senderName,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    color: EteyeloColors.primaryDark,
                  ),
                ),
              ),
            ),
          if (replyBody != null && replyBody!.trim().isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: const Border(
                  left: BorderSide(
                    color: EteyeloColors.primaryDark,
                    width: 2.5,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    replySender?.isNotEmpty == true
                        ? replySender!
                        : "Message",
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: EteyeloColors.primaryDark,
                    ),
                  ),
                  LinkifiedText(
                    text: replyBody!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.25,
                      color: EteyeloColors.subtitle,
                    ),
                  ),
                ],
              ),
            ),
          for (final raw in attachments)
            if (raw is Map)
              Padding(
                padding: EdgeInsets.only(
                  bottom: (!_isPlaceholderBody || attachments.length > 1)
                      ? 4
                      : 2,
                ),
                child: _AttachmentView(
                  attachment: Map<String, dynamic>.from(raw),
                  mine: mine,
                  maxWidth: maxW - 24,
                ),
              ),
          if (call != null)
            _CallMessageCard(info: call!, textColor: textColor)
          else if (!_isPlaceholderBody || attachments.isEmpty)
            LinkifiedText(
              text: body,
              enabled: !deleted,
              style: TextStyle(
                fontSize: 15.2,
                height: 1.3,
                fontWeight: FontWeight.w500,
                fontStyle: deleted ? FontStyle.italic : FontStyle.normal,
                color: deleted ? EteyeloColors.subtitle : textColor,
              ),
              linkColor: mine
                  ? EteyeloColors.primaryDarker
                  : EteyeloColors.primaryDark,
            ),
          Opacity(opacity: 0, child: _metaRow()),
        ],
    );

    final card = SizedBox(
      width: bubbleW,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: _radius,
          border: Border.all(
            color: dark
                ? Colors.white.withValues(alpha: 0.16)
                : const Color(0xFFB4BCC6),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.28 : 0.14),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 4),
          child: Stack(
            children: [
              bubbleBody,
              Positioned(
                right: 0,
                bottom: 0,
                child: _metaRow(),
              ),
            ],
          ),
        ),
      ),
    );

    final bubble = Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        if (showTail)
          Positioned(
            bottom: 0,
            right: mine ? -5.5 : null,
            left: mine ? null : -5.5,
            child: CustomPaint(
              size: const Size(7.5, 11),
              painter: _BubbleTailPainter(color: bg, mine: mine),
            ),
          ),
      ],
    );

    final menuBtn = showMenuButton && onMenuTap != null
        ? Padding(
            padding: EdgeInsets.only(
              left: mine ? 0 : 2,
              right: mine ? 2 : 0,
              bottom: showTail ? 4 : 2,
            ),
            child: _MessageMenuButton(onTap: onMenuTap!),
          )
        : null;

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!mine) ...[
          SizedBox(
            width: 28,
            height: 28,
            child: showAvatar
                ? GestureDetector(
                    onTap: onAvatarTap,
                    child: UserAvatar(
                      image: senderImage,
                      name: senderName,
                      radius: 14,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (mine && menuBtn != null) menuBtn,
                bubble,
                if (!mine && menuBtn != null) menuBtn,
              ],
            ),
          ),
        ),
      ],
    );
    if (!appearing) return row;
    return _SendArrival(
      animate: true,
      fromRight: mine,
      child: row,
    );
  }
}

bool _attachmentLooksLikeImage(Map<String, dynamic> attachment) {
  final kind = attachment["kind"]?.toString().toUpperCase() ?? "";
  if (kind == "IMAGE") return true;
  if (attachment["localBytes"] != null) {
    final mime = attachment["mimeType"]?.toString().toLowerCase() ?? "";
    if (mime.startsWith("image/")) return true;
  }
  final mime = attachment["mimeType"]?.toString().toLowerCase() ?? "";
  if (mime.startsWith("image/")) return true;
  final name = (attachment["fileName"] ?? attachment["filename"] ?? "")
      .toString()
      .toLowerCase();
  return name.endsWith(".png") ||
      name.endsWith(".jpg") ||
      name.endsWith(".jpeg") ||
      name.endsWith(".webp") ||
      name.endsWith(".gif") ||
      name.endsWith(".heic");
}

bool _attachmentLooksLikeAudio(Map<String, dynamic> attachment) {
  final kind = attachment["kind"]?.toString().toUpperCase() ?? "";
  if (kind == "AUDIO") return true;
  final mime = attachment["mimeType"]?.toString().toLowerCase() ?? "";
  if (mime.startsWith("audio/")) return true;
  final name = (attachment["fileName"] ?? attachment["filename"] ?? "")
      .toString()
      .toLowerCase();
  return name.endsWith(".m4a") ||
      name.endsWith(".aac") ||
      name.endsWith(".mp3") ||
      name.endsWith(".wav") ||
      name.endsWith(".ogg") ||
      name.endsWith(".opus") ||
      name.endsWith(".webm");
}

class _AttachmentView extends StatefulWidget {
  const _AttachmentView({
    required this.attachment,
    required this.mine,
    required this.maxWidth,
  });

  final Map<String, dynamic> attachment;
  final bool mine;
  final double maxWidth;

  @override
  State<_AttachmentView> createState() => _AttachmentViewState();
}

class _AttachmentViewState extends State<_AttachmentView> {
  final _player = AudioPlayer();
  StreamSubscription<void>? _completeSub;
  bool _playing = false;
  bool _loadingAudio = false;
  String? _audioError;
  bool _loadRemoteImage = false;

  @override
  void initState() {
    super.initState();
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Uint8List? _localAudioBytes() {
    final raw = widget.attachment["localBytes"];
    if (raw is Uint8List && raw.isNotEmpty) return raw;
    if (raw is List<int> && raw.isNotEmpty) return Uint8List.fromList(raw);
    return null;
  }

  Future<void> _toggleAudio(String? url) async {
    if (_playing) {
      await _player.stop();
      if (mounted) {
        setState(() {
          _playing = false;
          _audioError = null;
        });
      }
      return;
    }

    setState(() {
      _loadingAudio = true;
      _audioError = null;
    });

    try {
      // Libère le focus audio éventuellement pris par la sonnerie d'appel.
      await SoundService.instance.stopRingtone();
      final local = _localAudioBytes();
      if (local != null) {
        final mime = widget.attachment["mimeType"]?.toString() ?? "audio/mpeg";
        await _player.play(BytesSource(local, mimeType: mime));
      } else if (url != null && url.isNotEmpty) {
        await _player.setVolume(1.0);
        await _player.play(UrlSource(url, mimeType: "audio/mpeg"));
      } else {
        throw Exception("Audio indisponible");
      }
      if (mounted) {
        setState(() {
          _playing = true;
          _loadingAudio = false;
        });
      }
    } catch (e) {
      debugPrint("[audio] play failed: $e");
      if (mounted) {
        setState(() {
          _playing = false;
          _loadingAudio = false;
          _audioError = "Lecture impossible";
        });
      }
    }
  }

  void _openFullscreen(ImageProvider provider) {
    final url = resolveImageUrl(widget.attachment["url"]);
    final localRaw = widget.attachment["localBytes"];
    Uint8List? local;
    if (localRaw is Uint8List) {
      local = localRaw;
    } else if (localRaw is List<int>) {
      local = Uint8List.fromList(localRaw);
    }
    final fileName = (widget.attachment["fileName"] ??
            widget.attachment["filename"] ??
            "klambo")
        .toString()
        .replaceAll(RegExp(r"\.[^.]+$"), "");

    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.92),
        pageBuilder: (context, animation, _) {
          return FadeTransition(
            opacity: animation,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: SafeArea(
                  child: Stack(
                    children: [
                      Center(
                        child: InteractiveViewer(
                          minScale: 0.8,
                          maxScale: 4,
                          child: Image(
                            image: provider,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: IconButton(
                          tooltip: kIsWeb
                              ? "Télécharger"
                              : "Enregistrer dans la galerie",
                          onPressed: () async {
                            try {
                              await saveImageUrlToDeviceGallery(
                                url: url,
                                name: fileName,
                                localBytes: local,
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    kIsWeb
                                        ? "Image téléchargée"
                                        : "Image enregistrée dans la galerie",
                                  ),
                                ),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    "Enregistrement impossible : $e",
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(
                            Icons.download_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _imageFrame({required Widget child, required ImageProvider provider}) {
    final width = widget.maxWidth.clamp(160.0, 280.0);
    const height = 180.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openFullscreen(provider),
        borderRadius: BorderRadius.circular(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: width,
            height: height,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _audioBubble({required String? url}) {
    final durationMs = widget.attachment["durationMs"];
    final secs = durationMs is num ? (durationMs / 1000).round() : null;
    final label = _audioError ??
        (secs != null ? "Audio · ${secs}s" : "Audio");
    final canPlay = url != null || _localAudioBytes() != null;

    return Material(
      color: Colors.black.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: !canPlay || _loadingAudio ? null : () => _toggleAudio(url),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loadingAudio)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Icon(
                  _playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                  color: _audioError != null
                      ? Colors.red.shade700
                      : EteyeloColors.primaryDark,
                  size: 28,
                ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _audioError != null
                      ? Colors.red.shade700
                      : widget.mine
                          ? EteyeloColors.bubbleOutgoingText
                          : EteyeloColors.bubbleIncomingText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.attachment["kind"]?.toString().toUpperCase() ?? "FILE";
    final url = resolveImageUrl(widget.attachment["url"]);
    final fileName =
        widget.attachment["fileName"]?.toString() ?? "Pièce jointe";
    final localBytes = widget.attachment["localBytes"];

    if (_attachmentLooksLikeImage(widget.attachment)) {
      if (localBytes is List<int> && localBytes.isNotEmpty) {
        final bytes = localBytes is Uint8List
            ? localBytes
            : Uint8List.fromList(localBytes);
        final provider = MemoryImage(bytes);
        return _imageFrame(
          provider: provider,
          child: Image(
            image: provider,
            fit: BoxFit.cover,
            width: widget.maxWidth.clamp(160.0, 280.0),
            height: 180,
            gaplessPlayback: true,
          ),
        );
      }

      if (url != null) {
        final saver = DataSaverPrefs.instance.effectiveEnabled;
        if (saver && !_loadRemoteImage) {
          final width = widget.maxWidth.clamp(160.0, 280.0);
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _loadRemoteImage = true),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: width,
                height: 180,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8EEF5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.data_saver_on_outlined,
                      color: Colors.blueGrey.shade600,
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        L10n.of(LocaleController.instance.lang)
                            .dataSaverTapToLoad,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final provider = CachedNetworkImageProvider(url);
        return _imageFrame(
          provider: provider,
          child: CachedNetworkImage(
            imageUrl: url,
            width: widget.maxWidth.clamp(160.0, 280.0),
            height: 180,
            fit: BoxFit.cover,
            memCacheWidth: saver ? 480 : null,
            fadeInDuration: Duration.zero,
            fadeOutDuration: Duration.zero,
            placeholder: (_, __) => Container(
              width: widget.maxWidth.clamp(160.0, 280.0),
              height: 180,
              color: const Color(0xFFE8EEF5),
            ),
            errorWidget: (_, __, ___) => Image.network(
              url,
              width: widget.maxWidth.clamp(160.0, 280.0),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: widget.maxWidth.clamp(160.0, 280.0),
                height: 140,
                color: const Color(0xFFE8EEF5),
                alignment: Alignment.center,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_outlined, size: 28),
                    SizedBox(height: 6),
                    Text("Image indisponible", style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }

    if (_attachmentLooksLikeAudio(widget.attachment)) {
      return _audioBubble(url: url);
    }

    // PDF / autres fichiers : pastille nom (pas de prévisualisation contenu).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            kind == "FILE" || fileName.toLowerCase().endsWith(".pdf")
                ? Icons.picture_as_pdf_outlined
                : Icons.attach_file,
            color: EteyeloColors.primaryDark,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              fileName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: widget.mine
                    ? EteyeloColors.bubbleOutgoingText
                    : EteyeloColors.bubbleIncomingText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
