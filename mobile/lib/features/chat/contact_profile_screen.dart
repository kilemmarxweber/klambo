import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/core/l10n.dart";
import "package:klambo_messagerie/core/media_urls.dart";
import "package:klambo_messagerie/core/person_name.dart";
import "package:klambo_messagerie/core/phone_number.dart";
import "package:klambo_messagerie/features/auth/session_provider.dart";
import "package:klambo_messagerie/widgets/section_panel.dart";
import "package:klambo_messagerie/widgets/user_avatar.dart";
import "package:url_launcher/url_launcher.dart";

/// Fiche contact : identité + coordonnées (téléphone, rôle, établissements).
class ContactProfileScreen extends ConsumerStatefulWidget {
  const ContactProfileScreen({
    super.key,
    required this.name,
    this.prenom,
    this.image,
    this.telephone,
    this.roleLabel,
    this.branches = const [],
    this.userId,
    this.organizationId,
  });

  final String name;
  final String? prenom;
  final String? image;
  final String? telephone;
  final String? roleLabel;
  final List<String> branches;
  final String? userId;
  final String? organizationId;

  @override
  ConsumerState<ContactProfileScreen> createState() =>
      _ContactProfileScreenState();
}

class _ContactProfileScreenState extends ConsumerState<ContactProfileScreen> {
  String? _phone;
  bool _loadingPhone = false;

  String get _prenomLabel => personPrenom(widget.prenom);

  String get _nomLabel => personNom(name: widget.name);

  @override
  void initState() {
    super.initState();
    _phone = extractPhoneNumber(widget.telephone);
    if (_phone == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPhone());
    }
  }

  Future<void> _loadPhone() async {
    final userId = widget.userId;
    if (userId == null || userId.isEmpty) return;
    final orgId = widget.organizationId ??
        ref.read(sessionProvider).activeOrgId;
    if (orgId == null || orgId.isEmpty) return;
    setState(() => _loadingPhone = true);
    try {
      final repo = ref.read(messagingRepositoryProvider);
      final queries = <String>[
        if ((widget.prenom ?? "").trim().isNotEmpty) widget.prenom!.trim(),
        if (widget.name.trim().isNotEmpty) widget.name.trim(),
        "",
      ];
      String? found;
      for (final query in queries) {
        final data = await repo.searchRecipients(orgId, query: query);
        final items = (data["items"] as List?) ?? const [];
        for (final raw in items) {
          if (raw is! Map) continue;
          final id = raw["userId"]?.toString() ?? raw["id"]?.toString();
          if (id != userId) continue;
          found = extractPhoneNumber(raw);
          if (found != null) break;
        }
        if (found != null) break;
      }
      if (!mounted) return;
      setState(() => _phone = found ?? _phone);
    } catch (_) {
      // Le numéro reste « non renseigné » si l'annuaire ne répond pas.
    } finally {
      if (mounted) setState(() => _loadingPhone = false);
    }
  }

  void _openFullImage(BuildContext context) {
    final url = resolveImageUrl(widget.image);
    if (url == null) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.92),
        pageBuilder: (_, __, ___) =>
            _FullScreenImage(url: url, name: _nomLabel.isEmpty ? _prenomLabel : _nomLabel),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  Future<void> _callAndCopy(String phone) async {
    await Clipboard.setData(ClipboardData(text: phone));
    final uri = Uri.parse("tel:${dialablePhone(phone)}");
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ref.read(l10nProvider).phoneCopied),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final phone = _phone;
    final hasPhone = phone != null && phone.isNotEmpty;
    final first = _prenomLabel;
    final last = _nomLabel;
    final role = widget.roleLabel?.trim();
    final scheme = Theme.of(context).colorScheme;
    final avatarName = last.isNotEmpty ? last : first;

    return Scaffold(
      backgroundColor: ChatPalette.pageBackground(context),
      appBar: AppBar(
        title: Text(l10n.contactInfo),
      ),
      body: ListView(
        children: [
          SectionPanel(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => _openFullImage(context),
                  child: Hero(
                    tag: "contact-avatar-$avatarName",
                    child: UserAvatar(
                      image: widget.image,
                      name: avatarName.isEmpty ? "?" : avatarName,
                      radius: 56,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (last.isNotEmpty)
                  Text(
                    last,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                if (first.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    first,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: ChatPalette.subtitle(context),
                    ),
                  ),
                ],
                if (hasPhone) ...[
                  const SizedBox(height: 4),
                  Text(
                    phone,
                    style: TextStyle(
                      fontSize: 15,
                      color: ChatPalette.subtitle(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Text(
              l10n.contactSection,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ChatPalette.subtitle(context),
              ),
            ),
          ),
          SectionPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                if (first.isNotEmpty)
                  _InfoTile(
                    icon: Icons.person_outline,
                    title: l10n.firstName,
                    subtitle: first,
                  ),
                if (last.isNotEmpty)
                  _InfoTile(
                    icon: Icons.badge_outlined,
                    title: l10n.lastName,
                    subtitle: last,
                  ),
                _InfoTile(
                  icon: Icons.phone_outlined,
                  title: l10n.phoneNumber,
                  subtitle: _loadingPhone
                      ? "…"
                      : (hasPhone ? phone : l10n.phoneUnavailable),
                  muted: !hasPhone,
                  onTap: hasPhone ? () => _callAndCopy(phone) : null,
                  trailing: _loadingPhone
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : hasPhone
                          ? const Icon(Icons.call_outlined, size: 20)
                          : null,
                ),
                if (role != null && role.isNotEmpty)
                  _InfoTile(
                    icon: Icons.work_outline,
                    title: l10n.roleLabel,
                    subtitle: role,
                  ),
                if (widget.branches.isNotEmpty)
                  _InfoTile(
                    icon: Icons.apartment_outlined,
                    title: widget.branches.length == 1
                        ? l10n.branchLabel
                        : l10n.branchesLabel,
                    subtitle: widget.branches.join(" · "),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.muted = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final bool muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: EteyeloColors.primaryDark),
      title: Text(
        title,
        style: TextStyle(fontSize: 13, color: ChatPalette.subtitle(context)),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          fontStyle: muted ? FontStyle.italic : FontStyle.normal,
          color: muted
              ? ChatPalette.subtitle(context)
              : scheme.onSurface,
        ),
      ),
      trailing: trailing,
    );
  }
}

class _FullScreenImage extends StatelessWidget {
  const _FullScreenImage({required this.url, required this.name});

  final String url;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Hero(
                  tag: "contact-avatar-$name",
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const CircularProgressIndicator(
                      color: Colors.white,
                    ),
                    errorWidget: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white70,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
              ),
            ),
            Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: Text(
                name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
