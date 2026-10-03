import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:klambo_messagerie/core/app_page_route.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/core/media_urls.dart";
import "package:klambo_messagerie/core/person_name.dart";
import "package:klambo_messagerie/core/phone_number.dart";
import "package:klambo_messagerie/features/auth/session_provider.dart";
import "package:klambo_messagerie/features/chat/contact_profile_screen.dart";
import "package:klambo_messagerie/widgets/group_avatar.dart";
import "package:klambo_messagerie/widgets/section_panel.dart";
import "package:klambo_messagerie/widgets/user_avatar.dart";

/// Fiche d'un groupe : photo assemblée, nom, et noms des admins.
class GroupProfileScreen extends ConsumerStatefulWidget {
  const GroupProfileScreen({
    super.key,
    required this.name,
    this.images = const [],
    this.adminNames = const [],
    this.organizationId,
    this.conversationId,
  });

  final String name;
  final List<String> images;
  final List<String> adminNames;
  final String? organizationId;
  final String? conversationId;

  @override
  ConsumerState<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends ConsumerState<GroupProfileScreen> {
  late String _name = widget.name;
  late List<String> _images = List<String>.of(widget.images);
  late List<_AdminRow> _admins = [
    for (final name in widget.adminNames)
      if (name.trim().isNotEmpty) _AdminRow(name: name.trim()),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final orgId = widget.organizationId;
    final conversationId = widget.conversationId;
    if (orgId == null ||
        orgId.isEmpty ||
        conversationId == null ||
        conversationId.isEmpty) {
      return;
    }
    try {
      final data = await ref.read(messagingRepositoryProvider).getGroupSettings(
            orgId,
            conversationId,
          );
      if (!mounted) return;
      final subject = data["subject"]?.toString().trim() ?? "";
      final me = ref.read(sessionProvider).me;
      final user = me?["user"];
      final myId = user is Map ? user["id"]?.toString() : null;
      final members = data["members"];
      final photos = <String>[];
      String? mine;
      final admins = <_AdminRow>[];
      if (members is List) {
        for (final raw in members) {
          if (raw is! Map) continue;
          final image = raw["image"]?.toString();
          if (resolveImageUrl(image) != null && image != null) {
            if (myId != null && raw["userId"]?.toString() == myId) {
              mine = image;
            } else {
              photos.add(image);
            }
          }
          if (raw["groupRole"]?.toString() != "ADMIN") continue;
          final name = displayPersonName(
            prenom: raw["prenom"]?.toString(),
            nom: raw["nom"]?.toString(),
            name: raw["name"]?.toString(),
          );
          if (name.isEmpty) continue;
          admins.add(
            _AdminRow(
              name: name,
              image: image,
              prenom: raw["prenom"]?.toString(),
              telephone: accountTelephone(raw) ?? extractPhoneNumber(raw),
              userId: raw["userId"]?.toString(),
              roleLabel: raw["roleLabel"]?.toString(),
            ),
          );
        }
      }
      setState(() {
        if (subject.isNotEmpty) _name = subject;
        final shown = photos.isNotEmpty
            ? photos
            : (mine != null ? [mine] : const <String>[]);
        if (shown.isNotEmpty) _images = shown;
        if (admins.isNotEmpty) _admins = admins;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = _name.trim().isEmpty ? "Groupe" : _name.trim();

    return Scaffold(
      backgroundColor: ChatPalette.pageBackground(context),
      appBar: AppBar(title: const Text("Groupe")),
      body: ListView(
        children: [
          SectionPanel(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              children: [
                GroupAvatar(images: _images, radius: 56),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Text(
              "Admins",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ChatPalette.subtitle(context),
              ),
            ),
          ),
          SectionPanel(
            padding: EdgeInsets.zero,
            child: _admins.isEmpty
                ? const ListTile(
                    title: Text("Aucun admin"),
                  )
                : Column(
                    children: [
                      for (final admin in _admins)
                        ListTile(
                          onTap: () {
                            Navigator.of(context).push(
                              AppPageRoute(
                                builder: (_) => ContactProfileScreen(
                                  name: admin.name,
                                  prenom: admin.prenom,
                                  image: admin.image,
                                  telephone: admin.telephone,
                                  roleLabel: admin.roleLabel,
                                  userId: admin.userId,
                                  organizationId: widget.organizationId,
                                ),
                              ),
                            );
                          },
                          leading: resolveImageUrl(admin.image) == null
                              ? const Icon(Icons.admin_panel_settings_outlined)
                              : UserAvatar(
                                  image: admin.image,
                                  name: admin.name,
                                  radius: 20,
                                ),
                          title: Text(admin.name),
                          subtitle: const Text("Admin"),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _AdminRow {
  const _AdminRow({
    required this.name,
    this.image,
    this.prenom,
    this.telephone,
    this.userId,
    this.roleLabel,
  });

  final String name;
  final String? image;
  final String? prenom;
  final String? telephone;
  final String? userId;
  final String? roleLabel;
}
