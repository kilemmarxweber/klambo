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

  String get _nomLabel => personNom(
        name: widget.name,
        prenom: widget.prenom,
      );

  @override
  void initState() {
    super.initState();
    _phone = _immediatePhone();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPhone());
  }

  /// Numéro du compte, sinon un numéro collé au prénom ou au nom,
  /// sans attendre l'annuaire.
  String? _immediatePhone() {
    return _phoneFrom(widget.telephone) ??
        findPhoneInText(widget.prenom) ??
        findPhoneInText(widget.name);
  }

  String? _phoneFrom(dynamic source) {
    return accountTelephone(source) ?? extractPhoneNumber(source);
  }

  /// Même prénom et même nom que la fiche, même si l'id annuaire diffère.
  String? _phoneMatchingName(Map data) {
    final items = data["items"];
    if (items is! List) return null;
    final wantFirst = personPrenom(widget.prenom).toLowerCase();
    final wantLast = personNom(
      prenom: widget.prenom,
      nom: widget.name,
      name: widget.name,
    ).toLowerCase();
    if (wantFirst.isEmpty && wantLast.isEmpty) return null;
    for (final raw in items) {
      if (raw is! Map) continue;
      final first = personPrenom(raw["prenom"]?.toString()).toLowerCase();
      final last = personNom(
        prenom: raw["prenom"]?.toString(),
        nom: raw["nom"]?.toString(),
        name: raw["name"]?.toString(),
      ).toLowerCase();
      final sameFirst = wantFirst.isNotEmpty && first == wantFirst;
      final sameLast = wantLast.isNotEmpty && last == wantLast;
      if (wantFirst.isNotEmpty && wantLast.isNotEmpty) {
        if (!sameFirst || !sameLast) continue;
      } else if (!sameFirst && !sameLast) {
        continue;
      }
      final found = _phoneFrom(raw);
      if (found != null) return found;
    }
    return null;
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
      String? found;
      try {
        final direct = await repo.contact(orgId, userId);
        found = phoneFromApiPayload(direct, userId: userId) ??
            _phoneMatchingName(direct);
      } catch (_) {}
      if (found == null) {
        final queries = <String>[
          if ((widget.prenom ?? "").trim().isNotEmpty) widget.prenom!.trim(),
          if (widget.name.trim().isNotEmpty) widget.name.trim(),
        ];
        for (final query in queries) {
          final data = await repo.searchRecipients(orgId, query: query);
          found = phoneFromApiPayload(data, userId: userId) ??
              _phoneMatchingName(data);
          if (found != null) break;
        }
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
        barrierColor: Colors.transparent,
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

class _FullScreenImage extends StatefulWidget {
  const _FullScreenImage({required this.url, required this.name});

  final String url;
  final String name;

  @override
  State<_FullScreenImage> createState() => _FullScreenImageState();
}

class _FullScreenImageState extends State<_FullScreenImage> {
  final _transform = TransformationController();
  double _dragY = 0;

  bool get _zoomed => _transform.value.getMaxScaleOnAxis() > 1.05;

  void _close() {
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_zoomed) return;
    setState(() => _dragY += details.delta.dy);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    // Zoom pendant le drag : ne pas fermer, mais annuler le décalage
    // sinon l'image reste décalée pendant le pan zoomé.
    if (_zoomed) {
      if (_dragY != 0) setState(() => _dragY = 0);
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    if (_dragY.abs() > 90 || velocity.abs() > 650) {
      _close();
      return;
    }
    setState(() => _dragY = 0);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragY.abs() / 280).clamp(0.0, 1.0);
    final bgAlpha = 0.92 * (1 - progress);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: bgAlpha),
      body: SafeArea(
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
              onTap: _zoomed ? null : _close,
              child: Center(
                child: Transform.translate(
                  offset: Offset(0, _dragY),
                  child: Opacity(
                    opacity: (1 - progress * 0.45).clamp(0.35, 1.0),
                    child: InteractiveViewer(
                      transformationController: _transform,
                      // À l’échelle 1, le pan vertical ferme ; zoomé = naviguer.
                      panEnabled: _zoomed,
                      minScale: 0.8,
                      maxScale: 4,
                      onInteractionEnd: (_) {
                        if (mounted) setState(() {});
                      },
                      child: Hero(
                        tag: "contact-avatar-${widget.name}",
                        child: CachedNetworkImage(
                          imageUrl: widget.url,
                          fit: BoxFit.contain,
                          placeholder: (_, __) =>
                              const CircularProgressIndicator(
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
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Opacity(
                opacity: (1 - progress).clamp(0.0, 1.0),
                child: IconButton(
                  onPressed: _close,
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                ),
              ),
            ),
            Positioned(
              bottom: 24,
              left: 24,
              right: 24,
              child: Opacity(
                opacity: (1 - progress).clamp(0.0, 1.0),
                child: Text(
                  widget.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
