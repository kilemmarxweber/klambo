import "package:flutter/material.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/core/l10n.dart";
import "package:klambo_messagerie/widgets/group_avatar.dart";
import "package:klambo_messagerie/widgets/user_avatar.dart";

/// Barre supérieure type WhatsApp, bleu Eteyelo, avec photo + titre.
class EteyeloMessagingAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const EteyeloMessagingAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.avatarImage,
    this.avatarName,
    this.onAvatarTap,
    this.actions = const [],
    this.showBack = false,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final String? avatarImage;
  final String? avatarName;
  final VoidCallback? onAvatarTap;
  final List<Widget> actions;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: showBack && onBack == null,
      leading: showBack
          ? (onBack != null
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: onBack,
                )
              : null)
          : leading ??
              (avatarName != null
                  ? Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: IconButton(
                        onPressed: onAvatarTap,
                        tooltip: LocaleController.instance.l10n.myProfile,
                        icon: UserAvatar(
                          image: avatarImage,
                          name: avatarName!,
                          radius: 18,
                        ),
                      ),
                    )
                  : null),
      titleSpacing: showBack ? 0 : 4,
      title: InkWell(
        onTap: onAvatarTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: actions,
      backgroundColor: EteyeloColors.primaryDark,
    );
  }
}

/// App bar conversation : retour + avatar contact + actions appel.
class EteyeloChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const EteyeloChatAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.peerImage,
    this.groupPhotos,
    required this.peerName,
    this.onProfileTap,
    this.actions = const [],
    this.showBack = true,
    this.onBack,
  });

  final String title;
  final String? subtitle;
  /// Si non null, remplace le texte [subtitle] (ex. indicateur « écrit… »).
  final Widget? subtitleWidget;
  final String? peerImage;
  /// Photos des membres du groupe. Null = conversation à une personne.
  final List<String>? groupPhotos;
  final String peerName;
  final VoidCallback? onProfileTap;
  final List<Widget> actions;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: showBack && onBack == null,
      leading: showBack && onBack != null
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: onBack,
            )
          : null,
      titleSpacing: 0,
      title: InkWell(
        onTap: onProfileTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Row(
            children: [
              groupPhotos != null
                  ? GroupAvatar(images: groupPhotos!, radius: 20)
                  : UserAvatar(
                      image: peerImage,
                      name: peerName,
                      radius: 20,
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitleWidget != null)
                      subtitleWidget!
                    else if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: actions,
      backgroundColor: EteyeloColors.primaryDark,
    );
  }
}
