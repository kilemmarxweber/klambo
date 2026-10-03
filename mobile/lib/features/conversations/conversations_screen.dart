import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:klambo_messagerie/core/app_page_route.dart";
import "package:klambo_messagerie/core/app_version.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/core/call_trace.dart";
import "package:klambo_messagerie/core/format_time.dart";
import "package:klambo_messagerie/core/l10n.dart";
import "package:klambo_messagerie/core/media_urls.dart";
import "package:klambo_messagerie/core/notification_service.dart";
import "package:klambo_messagerie/core/person_name.dart";
import "package:klambo_messagerie/core/phone_number.dart";
import "package:klambo_messagerie/core/publisher_info.dart";
import "package:klambo_messagerie/core/satisfaction_trace.dart";
import "package:klambo_messagerie/features/auth/my_profile_screen.dart";
import "package:klambo_messagerie/features/auth/session_provider.dart";
import "package:klambo_messagerie/features/calls/call_hub.dart";
import "package:klambo_messagerie/features/chat/chat_screen.dart";
import "package:klambo_messagerie/features/chat/split_chat.dart";
import "package:klambo_messagerie/features/chat/contact_profile_screen.dart";
import "package:klambo_messagerie/features/conversations/group_profile_screen.dart";
import "package:klambo_messagerie/features/conversations/new_chat_screen.dart";
import "package:klambo_messagerie/features/conversations/new_group_screen.dart";
import "package:klambo_messagerie/features/presence/presence_controller.dart";
import "package:klambo_messagerie/features/settings/settings_screen.dart";
import "package:klambo_messagerie/widgets/chat_wallpaper.dart";
import "package:klambo_messagerie/widgets/connection_sync_bar.dart";
import "package:klambo_messagerie/widgets/eteyelo_messaging_app_bar.dart";
import "package:klambo_messagerie/widgets/group_avatar.dart";
import "package:klambo_messagerie/widgets/user_avatar.dart";

class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() =>
      _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _fromCache = false;
  String? _error;
  String _searchQuery = "";
  String _filter = "all"; // all | unread | groups | archived
  final _searchCtrl = TextEditingController();
  final Set<String> _selectedIds = {};
  bool _selectionMode = false;
  ProviderSubscription<AsyncValue<Map<String, dynamic>>>? _eventsSub;
  Timer? _reloadDebounce;
  Timer? _pollTimer;
  PresenceController? _presence;
  bool _listPrimed = false;
  final Map<String, String> _lastMessageKeys = {};
  bool _narrowChatPushing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _openChatFullScreenIfNarrow();
  }

  /// Retour au téléphone en portrait : le fil reprend tout l'écran.
  void _openChatFullScreenIfNarrow() {
    if (useSplitConversationLayout(context) || _narrowChatPushing) return;
    final target = ref.read(splitChatProvider);
    if (target == null) return;
    _narrowChatPushing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (useSplitConversationLayout(context)) {
        _narrowChatPushing = false;
        return;
      }
      final current = ref.read(splitChatProvider);
      if (current == null) {
        _narrowChatPushing = false;
        return;
      }
      ref.read(splitChatProvider.notifier).state = null;
      await Navigator.of(context).push(
        AppPageRoute(builder: (_) => _chatFrom(current)),
      );
      _narrowChatPushing = false;
      if (mounted) _load(silent: true);
    });
  }

  ChatScreen _chatFrom(SplitChatTarget target, {bool embedded = false}) {
    return ChatScreen(
      key: ValueKey("chat-${target.organizationId}-${target.conversationId}"),
      embedded: embedded,
      organizationId: target.organizationId,
      conversationId: target.conversationId,
      title: target.title,
      peerUserId: target.peerUserId,
      peerImage: target.peerImage,
      memberImages: target.memberImages,
      peerTelephone: target.peerTelephone,
      peerPrenom: target.peerPrenom,
      peerNom: target.peerNom,
      peerPostnom: target.peerPostnom,
      peerRoleLabel: target.peerRoleLabel,
      peerBranches: target.peerBranches,
      noReply: target.noReply,
      conversationType: target.conversationType,
      myRole: target.myRole,
      repliesLocked: target.repliesLocked,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bindPresence();
      _load();
      _eventsSub = ref.listenManual(messagingEventsProvider, (_, next) {
        next.whenData((event) {
          final type = event["type"]?.toString() ?? "";
          if (type == "message.created" ||
              type == "message.updated" ||
              type == "message.deleted" ||
              type == "conversation.updated" ||
              type.startsWith("call.")) {
            _reloadDebounce?.cancel();
            _reloadDebounce = Timer(const Duration(milliseconds: 250), () {
              if (mounted) _load(silent: true);
            });
          }
        });
      });
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) _load(silent: true);
      });
    });
  }

  @override
  void dispose() {
    _presence?.removeListener(_onPresenceChanged);
    _eventsSub?.close();
    _reloadDebounce?.cancel();
    _pollTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onPresenceChanged() {
    if (mounted) setState(() {});
  }

  void _bindPresence() {
    final presence = ref.read(presenceProvider);
    if (identical(presence, _presence)) return;
    _presence?.removeListener(_onPresenceChanged);
    _presence = presence;
    presence?.addListener(_onPresenceChanged);
  }

  Future<void> _refreshPresenceSnapshot() async {
    _bindPresence();
    final session = ref.read(sessionProvider);
    final myId = session.me?["user"] is Map
        ? (session.me!["user"] as Map)["id"]?.toString()
        : null;
    final byOrg = <String, Set<String>>{};
    for (final item in _items) {
      final orgId = item["organizationId"]?.toString();
      final peerId = _peerUserId(item, myId);
      if (orgId == null || peerId == null) continue;
      byOrg.putIfAbsent(orgId, () => <String>{}).add(peerId);
    }
    if (byOrg.isEmpty) return;

    final hub = ref.read(callHubProvider);
    final repo = ref.read(messagingRepositoryProvider);
    for (final entry in byOrg.entries) {
      hub?.setActiveOrganization(entry.key);
      hub?.socket.queryPresence(
        organizationId: entry.key,
        userIds: entry.value.toList(),
      );
      try {
        final data = await repo.getPresence(
          entry.key,
          userIds: entry.value.toList(),
        );
        final items = data["items"];
        if (items is List) {
          ref.read(presenceProvider)?.applyRestItems(items);
        }
      } catch (_) {}
    }
  }

  Future<void> _load({bool silent = false}) async {
    final l10n = ref.read(l10nProvider);
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
        _fromCache = false;
      });
    }

    try {
      // Évite de recliquer refreshMe toutes les 5s (ça invalidait le CallHub).
      if (!silent) {
        try {
          await ref.read(sessionProvider.notifier).refreshMe();
        } catch (_) {
          // Garde le profil en cache si hors ligne.
        }
      }

      final session = ref.read(sessionProvider);
      final orgs = session.messagingOrganizations;

      if (orgs.isEmpty) {
        setState(() {
          _items = [];
          _loading = false;
          _error = session.organizations.isEmpty
              ? l10n.noOrg
              : l10n.messagingDisabled;
        });
        return;
      }

      final repo = ref.read(messagingRepositoryProvider);
      final merged = <Map<String, dynamic>>[];
      final errors = <String>[];
      var anyCache = false;

      for (final org in orgs) {
        final orgId = org["id"]?.toString();
        if (orgId == null) continue;
        final orgName = org["name"]?.toString() ?? l10n.organizationFallback;
        try {
          final data = await repo.listConversations(orgId, filter: _filter);
          if (data["fromCache"] == true) anyCache = true;
          final items = (data["items"] as List?) ?? [];
          for (final raw in items) {
            if (raw is! Map) continue;
            merged.add({
              ...Map<String, dynamic>.from(raw),
              "organizationId": orgId,
              "organizationName": orgName,
            });
          }
        } catch (e) {
          errors.add(e.toString());
        }
      }

      merged.sort((a, b) {
        final aAt = a["updatedAt"]?.toString() ?? "";
        final bAt = b["updatedAt"]?.toString() ?? "";
        return bAt.compareTo(aAt);
      });

      setState(() {
        _items = merged;
        _loading = false;
        _fromCache = anyCache && merged.isNotEmpty;
        if (merged.isEmpty && errors.isNotEmpty) {
          _error = errors.first;
        } else {
          _error = null;
        }
      });
      unawaited(_syncLauncherBadge(merged));
      unawaited(_refreshPresenceSnapshot());
      if (!anyCache) _chimeNewConversations(merged);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _chimeNewConversations(List<Map<String, dynamic>> items) {
    final session = ref.read(sessionProvider);
    final me = session.me?["user"];
    final myId = me is Map ? me["id"]?.toString() : null;
    final hub = ref.read(callHubProvider);

    if (!_listPrimed) {
      for (final item in items) {
        final convId = item["id"]?.toString();
        final key = _incomingKey(item);
        if (convId != null && key != null) _lastMessageKeys[convId] = key;
      }
      _listPrimed = true;
      return;
    }

    for (final item in items) {
      final convId = item["id"]?.toString();
      final key = _incomingKey(item);
      if (convId == null || key == null) continue;
      final prev = _lastMessageKeys[convId];
      _lastMessageKeys[convId] = key;
      if (prev == null || prev == key) continue;
      final senderId = _lastSenderId(item);
      if (senderId != null && senderId == myId) continue;
      final last = item["lastMessage"];
      final body = last is Map
          ? (last["body"]?.toString().trim().isNotEmpty == true
              ? last["body"].toString()
              : "Nouveau message")
          : "Nouveau message";
      final created = last is Map ? last["createdAt"]?.toString() ?? "" : "";
      final altKey = "$convId|$created|$body";
      final senderName = last is Map
          ? (last["senderName"]?.toString() ??
              (last["sender"] is Map
                  ? (last["sender"] as Map)["name"]?.toString()
                  : null))
          : null;
      final title = (senderName != null && senderName.isNotEmpty)
          ? senderName
          : (item["title"]?.toString() ?? "Klambo");
      final avatarRaw = last is Map
          ? (last["senderImage"] ??
              (last["sender"] is Map
                  ? (last["sender"] as Map)["image"]
                  : null) ??
              _peerParticipant(item, myId)?["image"])
          : _peerParticipant(item, myId)?["image"];
      unawaited(
        hub?.alertIncomingMessage(
          dedupeKey: key,
          aliasKey: key == altKey ? null : altKey,
          title: title,
          body: body,
          avatarUrl: resolveImageUrl(avatarRaw),
          conversationId: convId,
          organizationId: item["organizationId"]?.toString(),
        ),
      );
    }
  }

  String? _incomingKey(Map item) {
    final last = item["lastMessage"];
    final convId = item["id"]?.toString() ?? "";
    if (last is! Map) return null;
    final id = last["id"]?.toString() ?? last["messageId"]?.toString();
    if (id != null && id.isNotEmpty) return id;
    final created = last["createdAt"]?.toString() ?? "";
    final body = last["body"]?.toString() ?? "";
    if (created.isEmpty && body.isEmpty) return null;
    return "$convId|$created|$body";
  }

  String? _lastSenderId(Map item) {
    final last = item["lastMessage"];
    if (last is! Map) return null;
    final nested = last["sender"];
    return last["senderId"]?.toString() ??
        last["authorId"]?.toString() ??
        (nested is Map ? nested["id"]?.toString() : null);
  }

  Future<void> _syncLauncherBadge(List<Map<String, dynamic>> items) async {
    var total = 0;
    for (final item in items) {
      total += (item["unreadCount"] as num?)?.toInt() ?? 0;
    }
    await NotificationService.instance.syncBadgeFromServer(total);
  }

  /// Photos des autres membres. Sans image : on ignore la personne.
  List<String> _groupPhotoSources(Map item, String? myId) {
    final participants = item["participants"];
    if (participants is! List) return const [];
    final others = <String>[];
    String? mine;
    for (final raw in participants) {
      if (raw is! Map) continue;
      final image = raw["image"]?.toString();
      if (resolveImageUrl(image) == null || image == null) continue;
      final id = raw["userId"]?.toString();
      if (myId != null && id == myId) {
        mine = image;
        continue;
      }
      others.add(image);
    }
    if (others.isEmpty && mine != null) return [mine];
    return others;
  }

  List<String> _groupAdminNames(Map item) {
    final participants = item["participants"];
    if (participants is! List) return const [];
    final names = <String>[];
    for (final raw in participants) {
      if (raw is! Map) continue;
      if (raw["groupRole"]?.toString() != "ADMIN") continue;
      final label = displayPersonName(
        prenom: raw["prenom"]?.toString(),
        nom: raw["nom"]?.toString(),
        name: raw["name"]?.toString(),
      );
      if (label.isNotEmpty) names.add(label);
    }
    return names;
  }

  Map<String, dynamic>? _peerParticipant(Map item, String? myId) {
    final participants = item["participants"];
    if (participants is! List || myId == null) return null;
    for (final p in participants) {
      if (p is Map) {
        final id = p["userId"]?.toString() ??
            (p["user"] is Map ? p["user"]["id"]?.toString() : null);
        if (id != null && id != myId) {
          final map = Map<String, dynamic>.from(p);
          map["userId"] ??= id;
          if (p["user"] is Map) {
            final u = Map<String, dynamic>.from(p["user"] as Map);
            map["prenom"] ??= u["prenom"];
            map["nom"] ??= u["nom"];
            map["image"] ??= u["image"];
            map["name"] ??= u["name"];
            map["roleLabel"] ??= u["roleLabel"] ?? u["role"];
            map["telephone"] ??=
                u["telephone"] ?? u["phone"] ?? u["phoneNumber"];
            map["phoneNumber"] ??= u["phoneNumber"];
            map["branches"] ??= u["branches"];
          }
          map["telephone"] = accountTelephone(map) ??
              accountTelephone(p["user"]) ??
              extractPhoneNumber(map) ??
              extractPhoneNumber(p["user"]) ??
              map["telephone"];
          return map;
        }
      }
    }
    return null;
  }

  String? _peerUserId(Map item, String? myId) {
    return _peerParticipant(item, myId)?["userId"]?.toString();
  }

  List<String> _peerBranches(Map? peer) {
    final raw = peer?["branches"];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((b) => b["name"]?.toString() ?? "")
        .where((n) => n.isNotEmpty)
        .toList();
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      _selectionMode = _selectedIds.isNotEmpty;
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
    });
  }

  Future<void> _archiveSelected() async {
    final repo = ref.read(messagingRepositoryProvider);
    final targets = _items
        .where((i) => _selectedIds.contains(i["id"]?.toString()))
        .toList();
    final unarchive = _filter == "archived";
    for (final item in targets) {
      final orgId = item["organizationId"]?.toString();
      final id = item["id"]?.toString();
      if (orgId == null || id == null) continue;
      await repo.conversationAction(
        orgId,
        id,
        unarchive ? "unarchive" : "archive",
      );
    }
    _clearSelection();
    await _load(silent: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          unarchive
              ? "${targets.length} conversation(s) désarchivée(s)"
              : ref.read(l10nProvider).conversationArchived(targets.length),
        ),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Supprimer"),
        content: Text(
          count == 1
              ? "Cette discussion sera retirée de votre liste."
              : "$count discussions seront retirées de votre liste.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Supprimer"),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final repo = ref.read(messagingRepositoryProvider);
    final targets = _items
        .where((i) => _selectedIds.contains(i["id"]?.toString()))
        .toList();
    var removed = 0;
    try {
      for (final item in targets) {
        final orgId = item["organizationId"]?.toString();
        final id = item["id"]?.toString();
        if (orgId == null || id == null) continue;
        await repo.conversationAction(orgId, id, "delete");
        removed++;
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Suppression impossible pour le moment."),
        ),
      );
      if (removed == 0) return;
    }
    _clearSelection();
    await _load(silent: true);
    if (!mounted || removed == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed == 1
              ? "Discussion supprimée"
              : "$removed discussions supprimées",
        ),
      ),
    );
  }

  Future<void> _openChat(Map<String, dynamic> item, {String? titleOverride}) async {
    final session = ref.read(sessionProvider);
    final user = session.me?["user"];
    final myId = user is Map ? user["id"]?.toString() : null;
    final id = item["id"]?.toString() ?? "";
    final orgId = item["organizationId"]?.toString() ?? session.activeOrgId;
    if (orgId == null || id.isEmpty) return;
    final peer = _peerParticipant(item, myId);
    final isGroup = item["type"]?.toString() == "GROUP";
    final target = SplitChatTarget(
      organizationId: orgId,
      conversationId: id,
      title: titleOverride ?? item["title"]?.toString() ?? "Conversation",
      peerUserId: isGroup ? null : _peerUserId(item, myId),
      peerImage: isGroup ? null : peer?["image"]?.toString(),
      memberImages: isGroup ? _groupPhotoSources(item, myId) : const [],
      peerTelephone: isGroup
          ? null
          : (accountTelephone(peer) ?? extractPhoneNumber(peer)),
      peerPrenom: isGroup ? null : peer?["prenom"]?.toString(),
      peerNom: isGroup ? null : peer?["nom"]?.toString(),
      peerPostnom: isGroup ? null : peer?["postnom"]?.toString(),
      peerRoleLabel: isGroup ? null : peer?["roleLabel"]?.toString(),
      peerBranches: isGroup ? const [] : _peerBranches(peer),
      noReply: item["noReply"] == true ||
          (item["title"]?.toString().contains("· Notifications") ?? false),
      conversationType: item["type"]?.toString(),
      myRole: item["myRole"]?.toString(),
      repliesLocked: item["repliesLocked"] == true,
    );
    if (useSplitConversationLayout(context)) {
      ref.read(splitChatProvider.notifier).state = target;
      return;
    }
    await Navigator.of(context).push(
      AppPageRoute(builder: (_) => _chatFrom(target)),
    );
    if (mounted) _load(silent: true);
  }

  List<Map<String, dynamic>> get _filteredItems {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((item) {
      final title = item["title"]?.toString().toLowerCase() ?? "";
      final last = item["lastMessage"];
      final preview =
          last is Map ? (last["body"]?.toString().toLowerCase() ?? "") : "";
      return title.contains(q) || preview.contains(q);
    }).toList();
  }

  void _openMyProfile() {
    Navigator.of(context).push(
      AppPageRoute(builder: (_) => const MyProfileScreen()),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      AppPageRoute(builder: (_) => const SettingsScreen()),
    );
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

  Future<void> _pickOrgThenOpen(Widget Function() screenBuilder) async {
    final session = ref.read(sessionProvider);
    final orgs = session.messagingOrganizations;
    if (orgs.isEmpty) return;

    String? orgId = session.activeOrgId;
    if (orgId == null || !orgs.any((o) => o["id"]?.toString() == orgId)) {
      orgId = orgs.first["id"]?.toString();
    }

    if (orgs.length > 1) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    "Choisir l'établissement",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                ...orgs.map((o) {
                  final id = o["id"]?.toString() ?? "";
                  return ListTile(
                    leading: const Icon(Icons.apartment),
                    title: Text(o["name"]?.toString() ?? id),
                    selected: id == orgId,
                    onTap: () => Navigator.pop(ctx, id),
                  );
                }),
              ],
            ),
          );
        },
      );
      if (picked == null) return;
      orgId = picked;
    }

    if (orgId == null) return;
    await ref.read(sessionProvider.notifier).setActiveOrganization(orgId);
    ref.read(callHubProvider)?.setActiveOrganization(orgId);

    if (!mounted) return;
    await Navigator.of(context).push(
      AppPageRoute(builder: (_) => screenBuilder()),
    );
    if (mounted) _load();
  }

  Future<void> _openNewChat() =>
      _pickOrgThenOpen(() => const NewChatScreen());

  Future<void> _openNewGroup() =>
      _pickOrgThenOpen(() => const NewGroupScreen());

  Future<void> _showComposeChooser() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text("Nouveau message"),
              subtitle: const Text("Conversation à une personne"),
              onTap: () => Navigator.pop(ctx, "chat"),
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text("Nouveau groupe"),
              subtitle: const Text("Message à plusieurs personnes"),
              onTap: () => Navigator.pop(ctx, "group"),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == "chat") await _openNewChat();
    if (choice == "group") await _openNewGroup();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final l10n = ref.watch(l10nProvider);
    final user = session.me?["user"];
    final myId = user is Map ? user["id"]?.toString() : null;
    final userName = user is Map
        ? (user["name"]?.toString() ?? l10n.userFallback)
        : l10n.userFallback;
    final userImage = user is Map ? user["image"]?.toString() : null;
    final canCompose = session.messagingOrganizations.isNotEmpty;
    final multiOrg = session.messagingOrganizations.length > 1;
    final filtered = _filteredItems;
    final split = useSplitConversationLayout(context);
    final openChat = ref.watch(splitChatProvider);

    final page = Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: _selectionMode
          ? AppBar(
              backgroundColor: EteyeloColors.primaryDarker,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              ),
              title: Text("${_selectedIds.length} sélectionnée(s)"),
              actions: [
                IconButton(
                  tooltip: _filter == "archived" ? "Désarchiver" : "Archiver",
                  onPressed: _archiveSelected,
                  icon: Icon(
                    _filter == "archived"
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                ),
                IconButton(
                  tooltip: "Supprimer",
                  onPressed: _deleteSelected,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            )
          : EteyeloMessagingAppBar(
        title: "Klambocore",
        subtitle: userName,
        avatarImage: userImage,
        avatarName: userName,
        onAvatarTap: _openMyProfile,
        actions: [
          IconButton(
            tooltip: l10n.newMessage,
            onPressed: canCompose ? _showComposeChooser : null,
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: l10n.settings,
            icon: const Icon(Icons.more_vert),
            offset: const Offset(0, 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (value) {
              switch (value) {
                case "settings":
                  _openSettings();
                case "refresh":
                  _load();
                case "about":
                  _showAbout();
                case "logout":
                  unawaited(NotificationService.instance.clearBadge());
                  ref.read(sessionProvider.notifier).signOut();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: "settings",
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(l10n.settings),
                ),
              ),
              PopupMenuItem(
                value: "refresh",
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.refresh),
                  title: Text(l10n.refresh),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: "about",
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.info_outline),
                  title: Text(l10n.aboutApp),
                ),
              ),
              PopupMenuItem(
                value: "logout",
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(Icons.logout, color: Colors.red.shade700),
                  title: Text(
                    l10n.logout,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: canCompose
          ? FloatingActionButton(
              onPressed: _showComposeChooser,
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          if (_fromCache) const ConnectionSyncBar(),
          if (!_selectionMode)
            Container(
              color: EteyeloColors.primaryDark,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final entry in const [
                      ("all", "Toutes"),
                      ("unread", "Non lues"),
                      ("groups", "Groupes"),
                      ("archived", "Archives"),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(entry.$2),
                          selected: _filter == entry.$1,
                          showCheckmark: false,
                          onSelected: (_) {
                            if (_filter == entry.$1) return;
                            setState(() => _filter = entry.$1);
                            _listPrimed = false;
                            _lastMessageKeys.clear();
                            _load();
                          },
                          selectedColor: Colors.white,
                          labelStyle: TextStyle(
                            color: _filter == entry.$1
                                ? Colors.black
                                : Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                          backgroundColor: const Color(0xFF3B82F6),
                          surfaceTintColor: Colors.transparent,
                          side: BorderSide(
                            color: _filter == entry.$1
                                ? EteyeloColors.primary
                                : const Color(0xFF93C5FD),
                            width: _filter == entry.$1 ? 1.6 : 1.2,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Container(
            color: EteyeloColors.primaryDark,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: l10n.searchConversation,
                hintStyle: TextStyle(color: Colors.grey.shade600),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: ChatPalette.subtitle(context)),
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.forum_outlined,
                                    size: 64,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _searchQuery.isEmpty
                                        ? l10n.noConversations
                                        : l10n.noResults,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: ChatPalette.subtitle(context),
                                    ),
                                  ),
                                  if (_searchQuery.isEmpty && canCompose) ...[
                                    const SizedBox(height: 20),
                                    FilledButton.icon(
                                      onPressed: _openNewChat,
                                      icon: const Icon(Icons.chat),
                                      label: Text(l10n.writeMessage),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                indent: 76,
                                color: ChatPalette.divider(context),
                              ),
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                final id = item["id"]?.toString() ?? "";
                                final selected = _selectedIds.contains(id);
                                final opened = split &&
                                    !_selectionMode &&
                                    openChat?.conversationId == id;
                                final unread =
                                    (item["unreadCount"] as num?)?.toInt() ?? 0;
                                final last = item["lastMessage"];
                                final previewRaw = last is Map
                                    ? (last["body"]?.toString() ?? "")
                                    : "";
                                final callPreview =
                                    CallTraceInfo.tryParse(previewRaw);
                                final satisfactionPreview =
                                    SatisfactionTrace.tryParse(previewRaw);
                                final preview =
                                    satisfactionPreview?.preview ??
                                    callPreview?.label ??
                                    previewRaw;
                                final needsSatisfaction =
                                    (satisfactionPreview?.pendingCount ?? 0) > 0;
                                final lastAt = last is Map
                                    ? last["createdAt"]?.toString()
                                    : item["updatedAt"]?.toString();
                                final orgName =
                                    item["organizationName"]?.toString() ?? "";
                                final peer = _peerParticipant(item, myId);
                                final peerImage = peer?["image"]?.toString();
                                final rawTitle =
                                    item["title"]?.toString() ?? "Conversation";
                                final isGroup =
                                    item["type"]?.toString() == "GROUP";
                                final isNotice = rawTitle.contains(
                                  "· Notifications",
                                );
                                final title = (!isGroup && !isNotice)
                                    ? () {
                                        final label = displayPersonName(
                                          prenom: peer?["prenom"]?.toString(),
                                          nom: peer?["nom"]?.toString(),
                                          postnom: peer?["postnom"]?.toString(),
                                          name: peer?["name"]?.toString() ??
                                              rawTitle,
                                        );
                                        return label.isEmpty ? rawTitle : label;
                                      }()
                                    : rawTitle;
                                final subtitle = multiOrg && orgName.isNotEmpty
                                    ? (preview.isEmpty
                                        ? orgName
                                        : "$orgName · $preview")
                                    : preview;

                                return InkWell(
                                  onLongPress: () {
                                    if (id.isEmpty) return;
                                    _toggleSelect(id);
                                  },
                                  onTap: () {
                                    if (_selectionMode) {
                                      if (id.isEmpty) return;
                                      _toggleSelect(id);
                                      return;
                                    }
                                    _openChat(item, titleOverride: title);
                                  },
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? EteyeloColors.primary
                                              .withValues(alpha: 0.08)
                                          : opened
                                              ? EteyeloColors.primary
                                                  .withValues(alpha: 0.14)
                                              : Colors.transparent,
                                      border: opened
                                          ? const Border(
                                              left: BorderSide(
                                                color: EteyeloColors.primary,
                                                width: 3,
                                              ),
                                            )
                                          : null,
                                    ),
                                    child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        GestureDetector(
                                          onTap: () {
                                            if (_selectionMode) {
                                              _toggleSelect(id);
                                              return;
                                            }
                                            final orgId = item["organizationId"]
                                                    ?.toString() ??
                                                ref
                                                    .read(sessionProvider)
                                                    .activeOrgId;
                                            Navigator.of(context).push(
                                              AppPageRoute(
                                                builder: (_) => isGroup
                                                    ? GroupProfileScreen(
                                                        name: title,
                                                        images:
                                                            _groupPhotoSources(
                                                          item,
                                                          myId,
                                                        ),
                                                        adminNames:
                                                            _groupAdminNames(
                                                          item,
                                                        ),
                                                        organizationId: orgId,
                                                        conversationId: id,
                                                      )
                                                    : ContactProfileScreen(
                                                        name: title,
                                                        prenom: peer?["prenom"]
                                                            ?.toString(),
                                                        image: peerImage,
                                                        telephone:
                                                            accountTelephone(
                                                                    peer) ??
                                                                extractPhoneNumber(
                                                                    peer) ??
                                                                accountTelephone(
                                                                    item) ??
                                                                extractPhoneNumber(
                                                                    item),
                                                        roleLabel: peer?[
                                                                "roleLabel"]
                                                            ?.toString(),
                                                        branches:
                                                            _peerBranches(peer),
                                                        userId: _peerUserId(
                                                            item, myId),
                                                        organizationId: orgId,
                                                      ),
                                              ),
                                            );
                                          },
                                          child: Stack(
                                            children: [
                                              isGroup
                                                  ? GroupAvatar(
                                                      images: _groupPhotoSources(
                                                        item,
                                                        myId,
                                                      ),
                                                      radius: 28,
                                                    )
                                                  : UserAvatar(
                                                      image: peerImage,
                                                      name: title,
                                                      radius: 28,
                                                    ),
                                              if (!selected &&
                                                  (_presence?.isOnline(
                                                        _peerUserId(
                                                              item, myId) ??
                                                            "",
                                                      ) ??
                                                      false))
                                                Positioned(
                                                  right: 2,
                                                  bottom: 2,
                                                  child: Container(
                                                    width: 14,
                                                    height: 14,
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                          0xFF25D366),
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: Colors.white,
                                                        width: 2,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              if (selected)
                                                Positioned(
                                                  right: 0,
                                                  bottom: 0,
                                                  child: Container(
                                                    decoration:
                                                        const BoxDecoration(
                                                      color: EteyeloColors
                                                          .primaryDark,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    padding:
                                                        const EdgeInsets.all(
                                                            2),
                                                    child: const Icon(
                                                      Icons.check,
                                                      size: 14,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      title,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: unread > 0
                                                            ? FontWeight.w700
                                                            : FontWeight.w500,
                                                        color: const Color(
                                                          0xFF111B21,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  Text(
                                                    formatMessageTime(lastAt),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: unread > 0
                                                          ? EteyeloColors
                                                              .primary
                                                          : EteyeloColors
                                                              .subtitle,
                                                      fontWeight: unread > 0
                                                          ? FontWeight.w600
                                                          : FontWeight.w400,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      subtitle.isEmpty
                                                          ? " "
                                                          : subtitle,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        color: unread > 0
                                                            ? const Color(
                                                                0xFF111B21,
                                                              )
                                                            : EteyeloColors
                                                                .subtitle,
                                                        fontWeight: unread > 0
                                                            ? FontWeight.w500
                                                            : FontWeight.w400,
                                                      ),
                                                    ),
                                                  ),
                                                  if (unread > 0)
                                                    Container(
                                                      margin: const EdgeInsets
                                                          .only(left: 8),
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 7,
                                                        vertical: 2,
                                                      ),
                                                      decoration:
                                                          const BoxDecoration(
                                                        color: EteyeloColors
                                                            .unreadBadge,
                                                        borderRadius:
                                                            BorderRadius.all(
                                                          Radius.circular(12),
                                                        ),
                                                      ),
                                                      child: Text(
                                                        unread > 99
                                                            ? "99+"
                                                            : "$unread",
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  if (needsSatisfaction)
                                                    Container(
                                                      margin:
                                                          const EdgeInsets.only(left: 8),
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFB45309)
                                                            .withValues(alpha: 0.15),
                                                        borderRadius:
                                                            const BorderRadius.all(
                                                          Radius.circular(10),
                                                        ),
                                                      ),
                                                      child: const Text(
                                                        "Avis",
                                                        style: TextStyle(
                                                          color: Color(0xFF92400E),
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ],
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
          ),
        ],
      ),
    );

    if (!split) return page;

    final listWidth = conversationListPaneWidth(
      MediaQuery.sizeOf(context).width,
    );
    return PopScope(
      canPop: openChat == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ref.read(splitChatProvider.notifier).state = null;
      },
      child: ColoredBox(
        color: EteyeloColors.primaryDark,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: listWidth, child: page),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: ChatPalette.divider(context),
            ),
            Expanded(
              child: openChat == null
                  ? _SplitConversationPlaceholder(
                      message: l10n.selectConversation,
                    )
                  : _chatFrom(openChat, embedded: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitConversationPlaceholder extends StatelessWidget {
  const _SplitConversationPlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ChatWallpaper.baseFor(context),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 72,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: ChatPalette.subtitle(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
