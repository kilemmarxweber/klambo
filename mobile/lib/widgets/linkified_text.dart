import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:url_launcher/url_launcher.dart";

enum LinkMatchKind { url, phone }

class LinkMatch {
  const LinkMatch({
    required this.start,
    required this.end,
    required this.raw,
    required this.kind,
  });

  final int start;
  final int end;
  final String raw;
  final LinkMatchKind kind;

  String get display => raw;

  /// URL normalisée (ajoute https:// si www.).
  String get normalizedUrl {
    final t = raw.trim();
    if (t.toLowerCase().startsWith("http://") ||
        t.toLowerCase().startsWith("https://")) {
      return t;
    }
    return "https://$t";
  }

  /// Chiffres seulement pour tel: (E.164-ish).
  String get phoneDigits {
    final hasPlus = raw.trim().startsWith("+");
    final digits = raw.replaceAll(RegExp(r"\D"), "");
    return hasPlus ? "+$digits" : digits;
  }

  bool get isValidPhone {
    final d = phoneDigits.replaceAll("+", "");
    return d.length >= 8 && d.length <= 15;
  }
}

/// Détecte http(s)/www et numéros de téléphone dans un texte.
List<LinkMatch> findLinkMatches(String text) {
  if (text.isEmpty) return const [];

  final urlRe = RegExp(
    r'(?:(?:https?|ftp):\/\/|www\.)[^\s<>\[\]{}]+',
    caseSensitive: false,
  );
  // +243…, 0822…, (01) 23 45 67 89 — au moins ~8 chiffres au total.
  final phoneRe = RegExp(
    r"(?<![\w@./])(?:\+\d{1,3}[\s.\-]*)?(?:\(?\d{1,4}\)?[\s.\-]*)?\d(?:[\d\s.\-]{5,}\d)",
  );

  final matches = <LinkMatch>[];
  void addIfFree(LinkMatch m) {
    for (final e in matches) {
      if (m.start < e.end && m.end > e.start) return;
    }
    matches.add(m);
  }

  for (final m in urlRe.allMatches(text)) {
    var raw = m.group(0)!;
    // Trim punctuation trailing often glued to URLs.
    while (raw.isNotEmpty &&
        ".,);]!?:\"'".contains(raw[raw.length - 1])) {
      raw = raw.substring(0, raw.length - 1);
    }
    if (raw.length < 4) continue;
    addIfFree(
      LinkMatch(
        start: m.start,
        end: m.start + raw.length,
        raw: raw,
        kind: LinkMatchKind.url,
      ),
    );
  }

  for (final m in phoneRe.allMatches(text)) {
    final raw = m.group(0)!.trim();
    final candidate = LinkMatch(
      start: m.start,
      end: m.start + raw.length,
      raw: raw,
      kind: LinkMatchKind.phone,
    );
    if (!candidate.isValidPhone) continue;
    addIfFree(candidate);
  }

  matches.sort((a, b) => a.start.compareTo(b.start));
  return matches;
}

/// Texte avec liens / numéros soulignés + colorés, actions au tap.
class LinkifiedText extends StatefulWidget {
  const LinkifiedText({
    super.key,
    required this.text,
    required this.style,
    this.linkColor = EteyeloColors.primaryDark,
    this.maxLines,
    this.overflow,
    this.enabled = true,
  });

  final String text;
  final TextStyle style;
  final Color linkColor;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool enabled;

  @override
  State<LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<LinkifiedText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  TextStyle get _linkStyle => widget.style.copyWith(
        color: widget.linkColor,
        decoration: TextDecoration.underline,
        decorationColor: widget.linkColor,
        fontWeight: FontWeight.w600,
      );

  Future<void> _onTapMatch(LinkMatch match) async {
    if (!widget.enabled) return;
    await showLinkActions(context, match);
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final matches = widget.enabled
        ? findLinkMatches(widget.text)
        : const <LinkMatch>[];
    if (matches.isEmpty) {
      return Text(
        widget.text,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in matches) {
      if (m.start > cursor) {
        spans.add(
          TextSpan(
            text: widget.text.substring(cursor, m.start),
            style: widget.style,
          ),
        );
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => _onTapMatch(m);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: widget.text.substring(m.start, m.end),
          style: _linkStyle,
          recognizer: recognizer,
        ),
      );
      cursor = m.end;
    }
    if (cursor < widget.text.length) {
      spans.add(
        TextSpan(
          text: widget.text.substring(cursor),
          style: widget.style,
        ),
      );
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}

Future<void> showLinkActions(BuildContext context, LinkMatch match) async {
  final isUrl = match.kind == LinkMatchKind.url;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                match.display,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: EteyeloColors.primaryDark,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: EteyeloColors.primaryDark,
                ),
              ),
              subtitle: Text(
                isUrl ? "Lien" : "Numéro de téléphone",
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const Divider(height: 1),
            if (isUrl)
              ListTile(
                leading: const Icon(Icons.open_in_browser_rounded),
                title: const Text("Ouvrir dans le navigateur"),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _openUrl(match.normalizedUrl);
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.phone_rounded),
                title: const Text("Appeler"),
                subtitle: Text(match.phoneDigits),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _openTel(match.phoneDigits);
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(isUrl ? "Copier le lien" : "Copier le numéro"),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: match.display));
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isUrl ? "Lien copié" : "Numéro copié",
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<void> _openUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      debugPrint("[link] launchUrl returned false for $url");
    }
  } catch (e) {
    debugPrint("[link] open url failed: $e");
  }
}

Future<void> _openTel(String phone) async {
  final uri = Uri(scheme: "tel", path: phone);
  try {
    final ok = await launchUrl(uri);
    if (!ok) {
      debugPrint("[link] tel launch false for $phone");
    }
  } catch (e) {
    debugPrint("[link] tel failed: $e");
  }
}
