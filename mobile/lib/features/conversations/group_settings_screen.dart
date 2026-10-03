import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:klambo_messagerie/core/app_page_route.dart";
import "package:klambo_messagerie/core/person_name.dart";
import "package:klambo_messagerie/core/phone_number.dart";
import "package:klambo_messagerie/features/auth/session_provider.dart";
import "package:klambo_messagerie/features/chat/contact_profile_screen.dart";
import "package:klambo_messagerie/widgets/eteyelo_messaging_app_bar.dart";
import "package:klambo_messagerie/widgets/user_avatar.dart";

/// Paramètres d'un groupe : admins (max 5), verrouillage des réponses.
class GroupSettingsScreen extends ConsumerStatefulWidget {
  const GroupSettingsScreen({
    super.key,
    required this.organizationId,
    required this.conversationId,
    required this.title,
  });

  final String organizationId;
  final String conversationId;
  final String title;

  @override
  ConsumerState<GroupSettingsScreen> createState() =>
      _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(messagingRepositoryProvider).getGroupSettings(
            widget.organizationId,
            widget.conversationId,
          );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool get _iAmAdmin => _data?["myRole"]?.toString() == "ADMIN";

  Future<void> _toggleLock(bool locked) async {
    if (!_iAmAdmin || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(messagingRepositoryProvider).conversationAction(
            widget.organizationId,
            widget.conversationId,
            locked ? "lock_replies" : "unlock_replies",
          );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            locked
                ? "Réponses verrouillées — seuls les admins peuvent écrire"
                : "Réponses autorisées pour tous les membres",
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Impossible : $e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setRole(String userId, String role) async {
    if (!_iAmAdmin || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(messagingRepositoryProvider).conversationAction(
            widget.organizationId,
            widget.conversationId,
            "set_role",
            userId: userId,
            role: role,
          );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$e")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = ((_data?["members"] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final locked = _data?["repliesLocked"] == true;
    final adminCount = (_data?["adminCount"] as num?)?.toInt() ?? 0;
    final maxAdmins = (_data?["maxAdmins"] as num?)?.toInt() ?? 5;
    final subject = _data?["subject"]?.toString() ?? widget.title;

    return Scaffold(
      appBar: EteyeloMessagingAppBar(
        title: "Paramètres du groupe",
        subtitle: subject,
        showBack: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _data == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Text(
                      "$adminCount / $maxAdmins admins",
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Verrouiller les réponses"),
                      subtitle: const Text(
                        "Seuls les admins peuvent envoyer des messages",
                      ),
                      value: locked,
                      onChanged: _iAmAdmin && !_busy ? _toggleLock : null,
                    ),
                    if (!_iAmAdmin)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          "Seul un admin peut modifier ces réglages.",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    const Divider(height: 28),
                    Text(
                      "Membres (${members.length})",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final m in members) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () {
                          final label = displayPersonName(
                            prenom: m["prenom"]?.toString(),
                            nom: m["nom"]?.toString(),
                            postnom: m["postnom"]?.toString(),
                            name: m["name"]?.toString(),
                          );
                          Navigator.of(context).push(
                            AppPageRoute(
                              builder: (_) => ContactProfileScreen(
                                name: label.isNotEmpty
                                    ? label
                                    : (m["name"]?.toString() ?? "Membre"),
                                prenom: m["prenom"]?.toString(),
                                image: m["image"]?.toString(),
                                telephone: accountTelephone(m) ??
                                    extractPhoneNumber(m),
                                roleLabel: m["roleLabel"]?.toString(),
                                userId: m["userId"]?.toString(),
                                organizationId: widget.organizationId,
                              ),
                            ),
                          );
                        },
                        leading: UserAvatar(
                          image: m["image"]?.toString(),
                          name: displayPersonName(
                            prenom: m["prenom"]?.toString(),
                            nom: m["nom"]?.toString(),
                            postnom: m["postnom"]?.toString(),
                            name: m["name"]?.toString(),
                          ),
                          radius: 22,
                        ),
                        title: Text(
                          displayPersonName(
                            prenom: m["prenom"]?.toString(),
                            nom: m["nom"]?.toString(),
                            postnom: m["postnom"]?.toString(),
                            name: m["name"]?.toString(),
                          ),
                        ),
                        subtitle: Text(
                          [
                            if (m["groupRole"] == "ADMIN") "Admin",
                            if (m["isCreator"] == true) "Créateur",
                            m["roleLabel"]?.toString() ?? "",
                          ].where((e) => e.toString().isNotEmpty).join(" · "),
                        ),
                        trailing: _iAmAdmin
                            ? PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == "admin") {
                                    _setRole(
                                      m["userId"]?.toString() ?? "",
                                      "ADMIN",
                                    );
                                  } else if (v == "member") {
                                    _setRole(
                                      m["userId"]?.toString() ?? "",
                                      "MEMBER",
                                    );
                                  }
                                },
                                itemBuilder: (_) => [
                                  if (m["groupRole"] != "ADMIN")
                                    PopupMenuItem(
                                      value: "admin",
                                      enabled: adminCount < maxAdmins,
                                      child: Text(
                                        adminCount >= maxAdmins
                                            ? "Admin (max $maxAdmins atteint)"
                                            : "Nommer admin",
                                      ),
                                    ),
                                  if (m["groupRole"] == "ADMIN")
                                    const PopupMenuItem(
                                      value: "member",
                                      child: Text("Retirer admin"),
                                    ),
                                ],
                              )
                            : (m["groupRole"] == "ADMIN"
                                ? const Chip(
                                    label: Text("Admin"),
                                    visualDensity: VisualDensity.compact,
                                  )
                                : null),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      "Un admin peut retirer n'importe quel message du groupe "
                      "et gérer jusqu'à $maxAdmins admins.",
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
    );
  }
}
