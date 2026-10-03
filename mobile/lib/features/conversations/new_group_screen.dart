import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/core/person_name.dart";
import "package:klambo_messagerie/features/auth/session_provider.dart";
import "package:klambo_messagerie/features/chat/chat_screen.dart";
import "package:klambo_messagerie/widgets/chat_composer.dart";
import "package:klambo_messagerie/widgets/eteyelo_messaging_app_bar.dart";
import "package:klambo_messagerie/widgets/user_avatar.dart";
import "package:uuid/uuid.dart";

/// Création d'un groupe (multi-destinataires + nom).
class NewGroupScreen extends ConsumerStatefulWidget {
  const NewGroupScreen({super.key});

  @override
  ConsumerState<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends ConsumerState<NewGroupScreen> {
  final _searchCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  List<dynamic> _recipients = [];
  final Map<String, Map> _selected = {};
  bool _loading = false;
  bool _sending = false;
  String? _error;
  int _step = 0; // 0 = membres, 1 = nom + message

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search(""));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _subjectCtrl.dispose();
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
      final data = await ref
          .read(messagingRepositoryProvider)
          .searchRecipients(orgId, query: q);
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

  void _toggle(Map r) {
    final id = r["userId"]?.toString();
    if (id == null) return;
    setState(() {
      if (_selected.containsKey(id)) {
        _selected.remove(id);
      } else {
        _selected[id] = r;
      }
    });
  }

  Future<void> _create(
    String text,
    List<PendingAttachment> attachments,
  ) async {
    final orgId = ref.read(sessionProvider).activeOrgId;
    if (orgId == null) return;
    final subject = _subjectCtrl.text.trim();
    if (subject.isEmpty) {
      setState(() => _error = "Donnez un nom au groupe.");
      return;
    }
    if (_selected.isEmpty) {
      setState(() => _error = "Choisissez au moins un membre.");
      return;
    }
    if (text.isEmpty && attachments.isEmpty) {
      setState(() => _error = "Écrivez un premier message ou joignez un fichier.");
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final repo = ref.read(messagingRepositoryProvider);
      final firstBody = text.isNotEmpty
          ? text
          : (attachments.first.kind == PendingAttachmentKind.image
              ? "[image]"
              : attachments.first.kind == PendingAttachmentKind.audio
                  ? "[audio]"
                  : "[file]");

      final data = await repo.createConversation(
        orgId,
        recipientIds: _selected.keys.toList(),
        body: firstBody,
        subject: subject,
        asGroup: true,
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
        );
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            organizationId: orgId,
            conversationId: conversationId,
            title: subject,
            memberImages: [
              for (final member in _selected.values)
                if (member["image"]?.toString().trim().isNotEmpty == true)
                  member["image"].toString(),
            ],
            conversationType: "GROUP",
            myRole: "ADMIN",
            repliesLocked: false,
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
    return Scaffold(
      appBar: EteyeloMessagingAppBar(
        title: _step == 0 ? "Nouveau groupe" : "Nom du groupe",
        subtitle: _step == 0
            ? "${_selected.length} sélectionné(s)"
            : "Vous serez admin (max 5)",
        showBack: true,
        onBack: () {
          if (_step == 1) {
            setState(() => _step = 0);
          } else {
            Navigator.of(context).maybePop();
          }
        },
      ),
      body: _step == 0 ? _buildPickMembers() : _buildNameAndMessage(),
    );
  }

  Widget _buildPickMembers() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: "Rechercher un contact",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: EteyeloColors.chatInputBar,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
            onChanged: _search,
          ),
        ),
        if (_selected.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final entry in _selected.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InputChip(
                      avatar: const Icon(Icons.person, size: 16),
                      label: Text(
                        displayPersonName(
                          prenom: entry.value["prenom"]?.toString(),
                          nom: entry.value["nom"]?.toString(),
                          name: entry.value["name"]?.toString(),
                        ),
                      ),
                      onDeleted: () => setState(() => _selected.remove(entry.key)),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _recipients.length,
                  itemBuilder: (context, index) {
                    final r = _recipients[index] as Map;
                    final id = r["userId"]?.toString() ?? "";
                    final selected = _selected.containsKey(id);
                    final label = displayPersonName(
                      prenom: r["prenom"]?.toString(),
                      nom: r["nom"]?.toString(),
                      name: r["name"]?.toString(),
                    );
                    final shown = label.isEmpty ? "Contact" : label;
                    return ListTile(
                      selected: selected,
                      selectedTileColor:
                          EteyeloColors.primary.withValues(alpha: 0.08),
                      leading: UserAvatar(
                        image: r["image"]?.toString(),
                        name: shown,
                        radius: 22,
                      ),
                      title: Text(
                        shown,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(
                        selected
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        color: selected
                            ? EteyeloColors.primary
                            : Colors.grey,
                      ),
                      onTap: () => _toggle(r),
                    );
                  },
                ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton.icon(
              onPressed: _selected.isEmpty
                  ? null
                  : () => setState(() {
                        _error = null;
                        _step = 1;
                      }),
              icon: const Icon(Icons.arrow_forward),
              label: Text("Suivant (${_selected.length})"),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNameAndMessage() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _subjectCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: "Nom du groupe",
              hintText: "Ex. Parents 6e A",
              filled: true,
              fillColor: EteyeloColors.chatInputBar,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "${_selected.length + 1} membres · vous serez admin",
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
        ),
        const Spacer(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        ChatComposer(
          controller: _messageCtrl,
          sending: _sending,
          enabled: !_sending,
          hintText: "Premier message du groupe…",
          onSend: _create,
        ),
      ],
    );
  }
}
