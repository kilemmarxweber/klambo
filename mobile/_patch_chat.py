from pathlib import Path

path = Path(r"lib/features/chat/chat_screen.dart")
text = path.read_text(encoding="utf-8")

if 'import "dart:async";' not in text:
    text = 'import "dart:async";\n\n' + text

old_dispose = '''  @override
  void dispose() {
    _presence?.removeListener(_onPresenceChanged);
    // clear active chat if still this conversation
    try {
      final active = ref.read(activeConversationIdProvider);
      if (active == widget.conversationId) {
        ref.read(activeConversationIdProvider.notifier).state = null;
      }
    } catch (_) {}
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }'''

new_dispose = '''  ProviderSubscription<AsyncValue<Map<String, dynamic>>>? _eventsSub;
  StateController<String?>? _activeConvCtrl;
  bool _typingPeer = false;
  Timer? _typingClear;

  @override
  void dispose() {
    _eventsSub?.close();
    _typingClear?.cancel();
    _presence?.removeListener(_onPresenceChanged);
    if (_activeConvCtrl?.state == widget.conversationId) {
      _activeConvCtrl?.state = null;
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }'''

print("dispose", old_dispose in text)
if old_dispose in text:
    text = text.replace(old_dispose, new_dispose)

old_init = '''  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeConversationIdProvider.notifier).state =
          widget.conversationId;
      _load();
      _bindPresence();
    });
  }'''

new_init = '''  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activeConvCtrl = ref.read(activeConversationIdProvider.notifier);
      _activeConvCtrl!.state = widget.conversationId;
      _load(silent: false);
      _bindPresence();
      _eventsSub = ref.listenManual(messagingEventsProvider, (_, next) {
        next.whenData(_onRealtimeEvent);
      });
    });
  }

  void _onRealtimeEvent(Map<String, dynamic> event) {
    final type = event["type"]?.toString() ?? "";
    final convId = event["conversationId"]?.toString();
    if (convId != null && convId != widget.conversationId) return;

    if (type == "typing") {
      final uid = event["userId"]?.toString();
      final me = ref.read(sessionProvider).me?["user"];
      final myId = me is Map ? me["id"]?.toString() : null;
      if (uid == null || uid == myId) return;
      setState(() => _typingPeer = true);
      _typingClear?.cancel();
      _typingClear = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _typingPeer = false);
      });
      return;
    }

    if (type == "message.created" ||
        type == "message.updated" ||
        type == "message.deleted" ||
        type == "conversation.updated") {
      unawaited(_load(silent: true));
    }
  }'''

print("init", old_init in text)
if old_init in text:
    text = text.replace(old_init, new_init)

old_load = '''  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(messagingRepositoryProvider);
      final data = await repo.listMessages(
        widget.organizationId,
        widget.conversationId,
      );
      final items = (data["items"] as List?) ?? [];
      final fromCache = data["fromCache"] == true;
      setState(() {
        _messages = items.reversed.toList();
        _loading = false;
        _fromCache = fromCache;
        _sendError = null;
      });
      if (!fromCache) {
        await repo.conversationAction(
          widget.organizationId,
          widget.conversationId,
          "read",
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _sendError = e.toString();
      });
    }
  }'''

new_load = '''  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
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
      setState(() {
        _messages = mapped;
        _loading = false;
        _fromCache = fromCache;
        _sendError = null;
      });
      if (!fromCache) {
        await repo.conversationAction(
          widget.organizationId,
          widget.conversationId,
          "read",
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final max = _scroll.position.maxScrollExtent;
        if (silent) {
          _scroll.animateTo(
            max,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        } else {
          _scroll.jumpTo(max);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _sendError = e.toString();
      });
    }
  }

  Future<void> _editMessage(Map msg) async {
    final current = msg["body"]?.toString() ?? "";
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
        title: const Text("Supprimer le message"),
        content: const Text(
          "Ce message sera supprimé pour tout le monde dans la conversation.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Supprimer"),
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
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Suppression impossible : $e")),
      );
    }
  }

  void _onMessageLongPress(Map msg, bool mine) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mine) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text("Modifier"),
                onTap: () {
                  Navigator.pop(ctx);
                  _editMessage(msg);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text("Supprimer"),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteMessage(msg);
                },
              ),
            ] else
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text("Message reçu"),
                subtitle: Text("Appui long sur vos messages pour modifier."),
              ),
          ],
        ),
      ),
    );
  }'''

print("load", old_load in text)
if old_load in text:
    text = text.replace(old_load, new_load)

text = text.replace(
    "      await _load();\n    } catch (e) {\n      setState(() => _sendError = l10n.sendFailed);",
    "      await _load(silent: true);\n    } catch (e) {\n      setState(() => _sendError = l10n.sendFailed);",
)

text = text.replace(
    "    final subtitle = _presenceSubtitle(l10n);",
    '    final subtitle = _typingPeer ? "écrit…" : _presenceSubtitle(l10n);',
)

old_item = '''                          return Padding(
                            padding: EdgeInsets.only(
                              top: sameAsPrev ? 3 : 10,
                              bottom: sameAsNext ? 3 : 10,
                            ),
                            child: _MessageBubble(
                              body: msg["body"]?.toString() ?? "",
                              time: formatMessageTime(
                                msg["createdAt"]?.toString(),
                              ),
                              mine: mine,
                              senderName: msg["senderName"]?.toString() ?? "",
                              senderImage: msg["senderImage"]?.toString(),
                              showAvatar: !mine && !sameAsNext,
                              showSenderName: !mine && !sameAsPrev,
                              clusterTop: !sameAsPrev,
                              clusterBottom: !sameAsNext,
                              attachments: attachments,
                            ),
                          );'''

new_item = '''                          final edited = msg["editedAt"] != null;
                          return Padding(
                            padding: EdgeInsets.only(
                              top: sameAsPrev ? 3 : 10,
                              bottom: sameAsNext ? 3 : 10,
                            ),
                            child: GestureDetector(
                              onLongPress: () =>
                                  _onMessageLongPress(msg, mine),
                              child: _MessageBubble(
                                body: msg["body"]?.toString() ?? "",
                                time: formatMessageTime(
                                  msg["createdAt"]?.toString(),
                                ),
                                mine: mine,
                                edited: edited,
                                senderName: msg["senderName"]?.toString() ?? "",
                                senderImage: msg["senderImage"]?.toString(),
                                showAvatar: !mine && !sameAsNext,
                                showSenderName: !mine && !sameAsPrev,
                                clusterTop: !sameAsPrev,
                                clusterBottom: !sameAsNext,
                                attachments: attachments,
                              ),
                            ),
                          );'''
print("item", old_item in text)
if old_item in text:
    text = text.replace(old_item, new_item)

old_bubble_ctor = '''class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.body,
    required this.time,
    required this.mine,
    required this.senderName,
    required this.senderImage,
    required this.showAvatar,
    required this.showSenderName,
    required this.clusterTop,
    required this.clusterBottom,
    required this.attachments,
  });

  final String body;
  final String time;
  final bool mine;
  final String senderName;
  final String? senderImage;
  final bool showAvatar;
  final bool showSenderName;
  final bool clusterTop;
  final bool clusterBottom;
  final List attachments;

  BorderRadius get _radius {
    const soft = 18.0;
    const tip = 5.0;
    if (mine) {
      return BorderRadius.only(
        topLeft: Radius.circular(clusterTop ? soft : tip),
        topRight: const Radius.circular(soft),
        bottomLeft: Radius.circular(clusterBottom ? tip : soft),
        bottomRight: const Radius.circular(soft),
      );
    }
    return BorderRadius.only(
      topLeft: const Radius.circular(soft),
      topRight: Radius.circular(clusterTop ? soft : tip),
      bottomLeft: const Radius.circular(soft),
      bottomRight: Radius.circular(clusterBottom ? tip : soft),
    );
  }'''

new_bubble_ctor = '''class _MessageBubble extends StatelessWidget {
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
  });

  final String body;
  final String time;
  final bool mine;
  final bool edited;
  final String senderName;
  final String? senderImage;
  final bool showAvatar;
  final bool showSenderName;
  final bool clusterTop;
  final bool clusterBottom;
  final List attachments;

  BorderRadius get _radius {
    const soft = 18.0;
    const tip = 5.0;
    if (mine) {
      return BorderRadius.only(
        topLeft: const Radius.circular(soft),
        topRight: Radius.circular(clusterTop ? soft : tip),
        bottomLeft: const Radius.circular(soft),
        bottomRight: Radius.circular(clusterBottom ? tip : soft),
      );
    }
    return BorderRadius.only(
      topLeft: Radius.circular(clusterTop ? soft : tip),
      topRight: const Radius.circular(soft),
      bottomLeft: Radius.circular(clusterBottom ? tip : soft),
      bottomRight: const Radius.circular(soft),
    );
  }'''
print("bubble", old_bubble_ctor in text)
if old_bubble_ctor in text:
    text = text.replace(old_bubble_ctor, new_bubble_ctor)

old_time = '''              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time,
                    style: const TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.2,
                      color: EteyeloColors.bubbleMeta,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.done_all_rounded,
                      size: 14,
                      color: EteyeloColors.primary.withValues(alpha: 0.5),
                    ),
                  ],
                ],
              ),'''

new_time = '''              Row(
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
                    const SizedBox(width: 6),
                  ],
                  Text(
                    time,
                    style: const TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.2,
                      color: EteyeloColors.bubbleMeta,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.done_all_rounded,
                      size: 14,
                      color: EteyeloColors.primary.withValues(alpha: 0.5),
                    ),
                  ],
                ],
              ),'''
print("time", old_time in text)
if old_time in text:
    text = text.replace(old_time, new_time)

old_row = '''    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (mine) ...[
          bubble,
          const Spacer(),
        ] else ...[
          const Spacer(),
          bubble,
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            height: 28,
            child: showAvatar
                ? UserAvatar(
                    image: senderImage,
                    name: senderName,
                    radius: 14,
                  )
                : null,
          ),
        ],
      ],
    );'''

new_row = '''    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!mine) ...[
          SizedBox(
            width: 28,
            height: 28,
            child: showAvatar
                ? UserAvatar(
                    image: senderImage,
                    name: senderName,
                    radius: 14,
                  )
                : null,
          ),
          const SizedBox(width: 8),
          bubble,
          const Spacer(),
        ] else ...[
          const Spacer(),
          bubble,
        ],
      ],
    );'''
print("row", old_row in text)
if old_row in text:
    text = text.replace(old_row, new_row)

path.write_text(text, encoding="utf-8")
print("done", len(text.splitlines()))
