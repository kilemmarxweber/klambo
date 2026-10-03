import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/core/media_urls.dart";

/// Avatar de groupe : uniquement les membres qui ont une photo.
/// Les membres sans image ne contribuent pas d'initiales.
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({
    super.key,
    required this.images,
    this.radius = 24,
  });

  final List<String?> images;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final urls = <String>[];
    for (final raw in images) {
      final url = resolveImageUrl(raw);
      if (url == null || urls.contains(url)) continue;
      urls.add(url);
      if (urls.length == 4) break;
    }

    final size = radius * 2;
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: ColoredBox(
          color: EteyeloColors.primary,
          child: urls.isEmpty
              ? Icon(Icons.groups, color: Colors.white, size: radius)
              : _PhotoMosaic(urls: urls),
        ),
      ),
    );
  }
}

class _PhotoMosaic extends StatelessWidget {
  const _PhotoMosaic({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    const gap = 1.0;
    if (urls.length == 1) return _tile(urls[0]);
    if (urls.length == 2) {
      return Row(
        children: [
          Expanded(child: _tile(urls[0])),
          const SizedBox(width: gap),
          Expanded(child: _tile(urls[1])),
        ],
      );
    }
    if (urls.length == 3) {
      return Row(
        children: [
          Expanded(child: _tile(urls[0])),
          const SizedBox(width: gap),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _tile(urls[1])),
                const SizedBox(height: gap),
                Expanded(child: _tile(urls[2])),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _tile(urls[0])),
              const SizedBox(width: gap),
              Expanded(child: _tile(urls[1])),
            ],
          ),
        ),
        const SizedBox(height: gap),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _tile(urls[2])),
              const SizedBox(width: gap),
              Expanded(child: _tile(urls[3])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(String url) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, __) => const ColoredBox(color: Color(0x33FFFFFF)),
      errorWidget: (_, __, ___) => const ColoredBox(
        color: Color(0x33FFFFFF),
        child: Icon(Icons.person, color: Colors.white70, size: 16),
      ),
    );
  }
}
