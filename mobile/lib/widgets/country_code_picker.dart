import "package:flutter/material.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/core/country_dial_codes.dart";

/// Hauteur alignée sur un `TextField` Outline + contentPadding thème (14).
const kPhoneFieldHeight = 56.0;

Future<CountryDial?> showCountryDialPicker({
  required BuildContext context,
  required CountryDial selected,
  required String langCode,
  String title = "Pays",
  String searchHint = "Rechercher un pays…",
}) {
  return showModalBottomSheet<CountryDial>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return _CountryDialSheet(
        selected: selected,
        langCode: langCode,
        title: title,
        searchHint: searchHint,
      );
    },
  );
}

class CountryDialButton extends StatelessWidget {
  const CountryDialButton({
    super.key,
    required this.country,
    required this.onTap,
    this.enabled = true,
  });

  final CountryDial country;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = scheme.outline;

    return SizedBox(
      height: kPhoneFieldHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            height: kPhoneFieldHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: borderColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(country.flag, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 6),
                Text(
                  "+${country.dialCode}",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: enabled
                        ? scheme.onSurface
                        : scheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 22,
                  color: enabled
                      ? ChatPalette.subtitle(context)
                      : scheme.onSurface.withValues(alpha: 0.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountryDialSheet extends StatefulWidget {
  const _CountryDialSheet({
    required this.selected,
    required this.langCode,
    required this.title,
    required this.searchHint,
  });

  final CountryDial selected;
  final String langCode;
  final String title;
  final String searchHint;

  @override
  State<_CountryDialSheet> createState() => _CountryDialSheetState();
}

class _CountryDialSheetState extends State<_CountryDialSheet> {
  late final List<CountryDial> _all = prioritizedCountries();
  late List<CountryDial> _filtered = _all;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filter(String q) {
    final needle = q.trim().toLowerCase();
    setState(() {
      if (needle.isEmpty) {
        _filtered = _all;
        return;
      }
      _filtered = _all.where((c) {
        final name = c.nameFor(widget.langCode).toLowerCase();
        return name.contains(needle) ||
            c.iso2.toLowerCase().contains(needle) ||
            c.dialCode.contains(needle) ||
            "+${c.dialCode}".contains(needle);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.85;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              widget.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _filter,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (context, index) {
                final c = _filtered[index];
                final selected = c.iso2 == widget.selected.iso2 &&
                    c.dialCode == widget.selected.dialCode;
                return ListTile(
                  leading: Text(c.flag, style: const TextStyle(fontSize: 28)),
                  title: Text(c.nameFor(widget.langCode)),
                  subtitle: Text("+${c.dialCode}"),
                  trailing: selected
                      ? const Icon(Icons.check, color: EteyeloColors.primary)
                      : null,
                  onTap: () => Navigator.pop(context, c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
