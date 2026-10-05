import "dart:convert";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:url_launcher/url_launcher.dart";

const kNotifyPrefix = "__NOTIFY__:";

/// Carte scolaire structurée (`__NOTIFY__:{json}`) — alignée Eteyelo NotifyMessageCard.
class NotifyTrace {
  const NotifyTrace({
    required this.title,
    this.tone = "navy",
    this.intro,
    this.rows = const [],
    this.note,
    this.ctaLabel,
    this.ctaHref,
    this.brand,
  });

  final String title;
  final String tone;
  final String? intro;
  final List<NotifyRow> rows;
  final String? note;
  final String? ctaLabel;
  final String? ctaHref;
  final String? brand;

  /// Avis officiel-ish : tons navy/rose, ou titre type circulaires / avis.
  bool get suggestsOfficialAck {
    final t = tone.toLowerCase().trim();
    if (t == "navy" || t == "rose") return true;
    final folded = title.toLowerCase();
    const keys = [
      "avis",
      "officiel",
      "official",
      "circulaire",
      "communiqué",
      "communique",
      "convocation",
      "certifié",
      "certifie",
      "importante",
      "urgente",
      "urgent",
      "notice",
      "comunicado",
      "circular",
    ];
    for (final k in keys) {
      if (folded.contains(k)) return true;
    }
    return false;
  }

  String get preview {
    for (final r in rows) {
      if (r.kind == "secret" || r.kind == "highlight") {
        return "$title · ${r.label}";
      }
    }
    return title;
  }

  Color get headerColor {
    switch (tone) {
      case "amber":
        return const Color(0xFF92400E);
      case "emerald":
        return const Color(0xFF065F46);
      case "rose":
        return const Color(0xFF9F1239);
      default:
        return const Color(0xFF172554);
    }
  }

  static NotifyTrace? tryParse(String? body) {
    if (body == null) return null;
    final trimmed = body.trim();
    if (!trimmed.startsWith(kNotifyPrefix)) return null;
    try {
      final raw = jsonDecode(trimmed.substring(kNotifyPrefix.length));
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      final title = map["title"]?.toString().trim() ?? "";
      if (title.isEmpty) return null;
      final rowsRaw = (map["rows"] as List?) ?? const [];
      final rows = rowsRaw
          .whereType<Map>()
          .map((r) {
            final data = Map<String, dynamic>.from(r);
            final label = data["label"]?.toString().trim() ?? "";
            final value = data["value"]?.toString().trim() ?? "";
            if (label.isEmpty || value.isEmpty) return null;
            return NotifyRow(
              label: label,
              value: value,
              kind: _normalizeKind(data["kind"]?.toString()),
            );
          })
          .whereType<NotifyRow>()
          .toList();
      final cta = map["cta"];
      String? ctaLabel;
      String? ctaHref;
      if (cta is Map) {
        ctaLabel = cta["label"]?.toString().trim();
        ctaHref = cta["href"]?.toString().trim();
        if (ctaLabel == null ||
            ctaLabel.isEmpty ||
            ctaHref == null ||
            ctaHref.isEmpty) {
          ctaLabel = null;
          ctaHref = null;
        }
      }
      return NotifyTrace(
        title: title,
        tone: map["tone"]?.toString() ?? "navy",
        intro: map["intro"]?.toString(),
        rows: rows,
        note: map["note"]?.toString(),
        ctaLabel: ctaLabel,
        ctaHref: ctaHref,
        brand: map["brand"]?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _normalizeKind(String? kind) {
    switch (kind) {
      case "secret":
      case "highlight":
      case "link":
      case "email":
      case "phone":
        return kind;
      default:
        return null;
    }
  }
}

class NotifyRow {
  const NotifyRow({
    required this.label,
    required this.value,
    this.kind,
  });

  final String label;
  final String value;
  final String? kind;
}

/// Carte visuelle pour un message `__NOTIFY__`.
class NotifyMessageCard extends StatelessWidget {
  const NotifyMessageCard({
    super.key,
    required this.trace,
    this.showReadAck = false,
    this.acked = false,
    this.acking = false,
    this.onAck,
    this.ackLabel,
    this.ackedLabel,
  });

  final NotifyTrace trace;
  final bool showReadAck;
  final bool acked;
  final bool acking;
  final VoidCallback? onAck;
  final String? ackLabel;
  final String? ackedLabel;

  Future<void> _open(String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Material(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: trace.headerColor,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (trace.brand != null && trace.brand!.trim().isNotEmpty)
                    Text(
                      trace.brand!.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  if (trace.brand != null && trace.brand!.trim().isNotEmpty)
                    const SizedBox(height: 2),
                  Text(
                    trace.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (trace.intro != null && trace.intro!.trim().isNotEmpty) ...[
                    Text(
                      trace.intro!,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (trace.rows.isNotEmpty)
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < trace.rows.length; i++) ...[
                            if (i > 0)
                              const Divider(height: 1, color: Color(0xFFE2E8F0)),
                            _NotifyRowTile(
                              row: trace.rows[i],
                              onCopy: () => _copy(trace.rows[i].value),
                              onOpen: _open,
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (trace.note != null && trace.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      trace.note!,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                  if (trace.ctaHref != null && trace.ctaLabel != null) ...[
                    const SizedBox(height: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: trace.headerColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => _open(trace.ctaHref!),
                      child: Text(trace.ctaLabel!),
                    ),
                  ],
                  if (showReadAck) ...[
                    const SizedBox(height: 12),
                    if (acked)
                      Row(
                        children: [
                          Icon(
                            Icons.verified_outlined,
                            size: 16,
                            color: trace.headerColor,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              ackedLabel ?? "Lecture confirmée",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: trace.headerColor,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: trace.headerColor,
                          side: BorderSide(
                            color: trace.headerColor.withValues(alpha: 0.45),
                          ),
                          minimumSize: const Size.fromHeight(40),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: acking ? null : onAck,
                        child: acking
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(ackLabel ?? "Accusé de lecture"),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotifyRowTile extends StatelessWidget {
  const _NotifyRowTile({
    required this.row,
    required this.onCopy,
    required this.onOpen,
  });

  final NotifyRow row;
  final VoidCallback onCopy;
  final Future<void> Function(String href) onOpen;

  IconData? get _icon {
    switch (row.kind) {
      case "secret":
        return Icons.key_rounded;
      case "highlight":
        return Icons.auto_awesome;
      case "email":
        return Icons.mail_outline;
      case "phone":
        return Icons.phone_outlined;
      case "link":
        return Icons.open_in_new;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final secret = row.kind == "secret";
    final highlight = row.kind == "highlight";
    final bg = secret
        ? const Color(0xFFFFFBEB)
        : highlight
            ? const Color(0xFFECFDF5)
            : Colors.transparent;

    return Material(
      color: bg,
      child: InkWell(
        onTap: () {
          if (row.kind == "link") {
            onOpen(row.value);
          } else if (row.kind == "email") {
            onOpen("mailto:${row.value}");
          } else if (row.kind == "phone") {
            onOpen("tel:${row.value}");
          } else if (secret) {
            onCopy();
          }
        },
        onLongPress: onCopy,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_icon != null) ...[
                    Icon(_icon, size: 14, color: const Color(0xFF64748B)),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      row.label.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (secret || highlight)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: secret
                          ? const Color(0xFFFCD34D)
                          : const Color(0xFF6EE7B7),
                    ),
                  ),
                  child: Text(
                    row.value,
                    style: TextStyle(
                      fontSize: secret ? 14 : 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: secret ? "monospace" : null,
                      color: secret
                          ? const Color(0xFF78350F)
                          : const Color(0xFF064E3B),
                    ),
                  ),
                )
              else
                Text(
                  row.kind == "link"
                      ? row.value
                          .replaceFirst(RegExp(r"^https?://"), "")
                          .replaceAll(RegExp(r"/$"), "")
                      : row.value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: row.kind == "link"
                        ? const Color(0xFF1D4ED8)
                        : const Color(0xFF1E293B),
                    decoration: row.kind == "link"
                        ? TextDecoration.underline
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
