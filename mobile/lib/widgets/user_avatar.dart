import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/core/media_urls.dart";

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.image,
    required this.name,
    this.radius = 24,
    this.backgroundColor,
  });

  final String? image;
  final String name;
  final double radius;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final url = resolveImageUrl(image);
    final initials = initialsFromName(name);
    final bg = backgroundColor ?? EteyeloColors.primary;

    if (url == null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.72,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: bg.withValues(alpha: 0.15),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          placeholder: (_, __) => _InitialsFallback(
            initials: initials,
            radius: radius,
            bg: bg,
          ),
          errorWidget: (_, __, ___) => _InitialsFallback(
            initials: initials,
            radius: radius,
            bg: bg,
          ),
        ),
      ),
    );
  }
}

class _InitialsFallback extends StatelessWidget {
  const _InitialsFallback({
    required this.initials,
    required this.radius,
    required this.bg,
  });

  final String initials;
  final double radius;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.72,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
