import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/core/l10n.dart";
import "package:klambo_messagerie/core/person_name.dart";
import "package:klambo_messagerie/core/phone_number.dart";
import "package:klambo_messagerie/features/auth/session_provider.dart";
import "package:klambo_messagerie/features/chat/chat_screen.dart";
import "package:klambo_messagerie/widgets/chat_composer.dart";
import "package:klambo_messagerie/widgets/eteyelo_messaging_app_bar.dart";
import "package:klambo_messagerie/widgets/user_avatar.dart";
import "package:uuid/uuid.dart";

class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final _searchCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  List<dynamic> _recipients = [];
  Map? _selected;
  bool _loading = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search(""));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final orgId = ref.read(sessionProvider).activeOrgId;
    if (orgId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(messagingRepositoryProvider);
      final data = await repo.searchRecipients(orgId, query: q);
      setState(() {
        _recipients = (data["items"] as List?) ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _placeholderFor(PendingAttachment att) {
    switch (att.kind) {
      case PendingAttachmentKind.image:
        return "[image]";
      case PendingAttachmentKind.pdf:
        return "[file]";
      case PendingAttachmentKind.audio:
        return "[audio]";
    }
  }

  Future<void> _start(
    String text,
    List<PendingAttachment> attachments,
  ) async {
    final orgId = ref.read(sessionProvider).activeOrgId;
    final selected = _selected;
    final l10n = ref.read(l10nProvider);
    if (orgId == null || selected == null) return;
    if (text.isEmpty && attachments.isEmpty) {
      setState(() => _error = l10n.writeOrAttach);
      return;
    }
    final userId = selected["userId"]?.toString();
    if (userId == null) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final repo = ref.read(messagingRepositoryProvider);
      final firstBody =
          text.isNotEmpty ? text : _placeholderFor(attachments.first);

      final data = await repo.createConversation(
        orgId,
        recipientIds: [userId],
        body: firstBody,
        clientMessageId: const Uuid().v4(),
      );
      final conversationId = data["conversationId"]?.toString();
      if (conversationId == null || !mounted) return;

      var captionUsed = text.isNotEmpty;
      for (final att in attachments) {
        final caption = (!captionUsed && text.isNotEmpty) ? text : "";
        if (caption.isNotEmpty) captionUsed = true;
        await repo.sendMediaMessage(
          orgId,
          conversationId,
          bytes: att.bytes,
          filename: att.filename,
          mimeType: att.mimeType,
          body: caption,
          clientMessageId: const Uuid().v4(),
          durationMs: att.durationMs,
          peerUserId: userId,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            organizationId: orgId,
            conversationId: conversationId,
            title: () {
              final label = displayPersonName(
                prenom: selected["prenom"]?.toString(),
                nom: selected["nom"]?.toString(),
                postnom: selected["postnom"]?.toString(),
                name: selected["name"]?.toString(),
              );
              return label.isEmpty ? l10n.conversationFallback : label;
            }(),
            conversationType: "DIRECT",
            peerUserId: userId,
            peerImage: selected["image"]?.toString(),
            peerTelephone: extractPhoneNumber(selected),
            peerPrenom: selected["prenom"]?.toString(),
            peerNom: selected["nom"]?.toString(),
            peerPostnom: selected["postnom"]?.toString(),
            peerRoleLabel: selected["roleLabel"]?.toString(),
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    return Scaffold(
      appBar: EteyeloMessagingAppBar(
        title: l10n.newMessage,
        subtitle: l10n.chooseContact,
        showBack: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: l10n.searchContact,
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: EteyeloColors.chatInputBar,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
              onChanged: (v) => _search(v),
            ),
          ),
          if (_selected != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InputChip(
                avatar: const Icon(Icons.person, size: 18),
                label: Text(
                  () {
                    final nom = personNom(
                      nom: _selected!["nom"]?.toString(),
                      name: _selected!["name"]?.toString(),
                    );
                    final prenom = personPrenom(_selected!["prenom"]?.toString());
                    if (nom.isEmpty) return prenom;
                    return nom;
                  }(),
                ),
                onDeleted: () => setState(() => _selected = null),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _recipients.isEmpty
                    ? Center(child: Text(l10n.noContactsFound))
                    : ListView.builder(
                        itemCount: _recipients.length,
                        itemBuilder: (context, index) {
                          final r = _recipients[index] as Map;
                          final selected =
                              _selected?["userId"] == r["userId"];
                          final nom = personNom(
                            nom: r["nom"]?.toString(),
                            name: r["name"]?.toString(),
                          );
                          final prenom = personPrenom(r["prenom"]?.toString());
                          final shown = nom.isEmpty ? "Contact" : nom;
                          return ListTile(
                            selected: selected,
                            selectedTileColor:
                                EteyeloColors.primary.withValues(alpha: 0.08),
                            leading: UserAvatar(
                              image: r["image"]?.toString(),
                              name: shown,
                              radius: 24,
                            ),
                            title: Text(
                              shown,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: prenom.isEmpty
                                ? null
                                : Text(
                                    prenom,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            trailing: selected
                                ? const Icon(Icons.check_circle,
                                    color: EteyeloColors.primary)
                                : null,
                            onTap: () => setState(() => _selected = r),
                          );
                        },
                      ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          ChatComposer(
            controller: _messageCtrl,
            sending: _sending,
            enabled: _selected != null && !_sending,
            hintText: l10n.firstMessageHint,
            onSend: _start,
          ),
        ],
      ),
    );
  }
}
