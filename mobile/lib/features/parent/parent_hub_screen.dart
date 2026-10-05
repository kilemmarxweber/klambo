import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:klambo_messagerie/core/app_theme.dart";
import "package:klambo_messagerie/core/l10n.dart";
import "package:klambo_messagerie/data/parent_repository.dart";
import "package:klambo_messagerie/features/auth/session_provider.dart";

final parentRepositoryProvider = Provider<ParentRepository>(
  (ref) => ParentRepository(ref.watch(apiClientProvider)),
);

/// Hub parent : enfants → frais / notes / bulletin (P1b).
class ParentHubScreen extends ConsumerStatefulWidget {
  const ParentHubScreen({super.key, required this.organizationId});

  final String organizationId;

  @override
  ConsumerState<ParentHubScreen> createState() => _ParentHubScreenState();
}

class _ParentHubScreenState extends ConsumerState<ParentHubScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _children = [];
  Map<String, dynamic>? _selected;
  String? _panel; // fees | grades | bulletin
  Map<String, dynamic>? _panelData;
  bool _panelLoading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadChildren());
  }

  Future<void> _loadChildren() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref
          .read(parentRepositoryProvider)
          .listChildren(widget.organizationId);
      if (!mounted) return;
      setState(() {
        _children = items;
        _selected = items.isEmpty ? null : items.first;
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

  Future<void> _openPanel(String panel) async {
    final child = _selected;
    final studentId = child?["studentId"]?.toString();
    if (studentId == null || studentId.isEmpty) return;
    setState(() {
      _panel = panel;
      _panelLoading = true;
      _panelData = null;
    });
    try {
      final repo = ref.read(parentRepositoryProvider);
      final data = switch (panel) {
        "fees" => await repo.feesStatus(
            organizationId: widget.organizationId,
            studentId: studentId,
          ),
        "grades" => await repo.gradesStatus(
            organizationId: widget.organizationId,
            studentId: studentId,
          ),
        _ => await repo.bulletinMeta(
            organizationId: widget.organizationId,
            studentId: studentId,
          ),
      };
      if (!mounted) return;
      setState(() {
        _panelData = data;
        _panelLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _panelLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(LocaleController.instance.lang);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(l10n.parentHubTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _children.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _children.isEmpty
                  ? Center(child: Text(l10n.parentNoChildren))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [
                        Text(
                          l10n.parentChooseChild,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final child in _children)
                              ChoiceChip(
                                label: Text(
                                  child["fullName"]?.toString() ?? "—",
                                ),
                                selected: _selected?["studentId"] ==
                                    child["studentId"],
                                onSelected: (_) {
                                  setState(() {
                                    _selected = child;
                                    _panel = null;
                                    _panelData = null;
                                  });
                                },
                              ),
                          ],
                        ),
                        if (_selected != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            [
                              _selected!["className"],
                              _selected!["branchName"],
                            ].where((e) => (e?.toString() ?? "").isNotEmpty)
                                .join(" · "),
                            style: TextStyle(
                              color: Colors.blueGrey.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        _MenuTile(
                          icon: Icons.payments_outlined,
                          title: l10n.parentFees,
                          onTap: () => unawaited(_openPanel("fees")),
                        ),
                        _MenuTile(
                          icon: Icons.school_outlined,
                          title: l10n.parentGrades,
                          onTap: () => unawaited(_openPanel("grades")),
                        ),
                        _MenuTile(
                          icon: Icons.picture_as_pdf_outlined,
                          title: l10n.parentBulletin,
                          onTap: () => unawaited(_openPanel("bulletin")),
                        ),
                        const SizedBox(height: 16),
                        if (_panelLoading)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_panel != null && _panelData != null)
                          _PanelBody(
                            panel: _panel!,
                            data: _panelData!,
                            l10n: l10n,
                            onPayFee: (fraisId) => unawaited(
                              _payFee(fraisId),
                            ),
                          ),
                      ],
                    ),
    );
  }

  Future<void> _payFee(String fraisId) async {
    final studentId = _selected?["studentId"]?.toString();
    if (studentId == null || studentId.isEmpty) return;
    final l10n = L10n.of(LocaleController.instance.lang);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await ref.read(parentRepositoryProvider).feesPayLink(
            organizationId: widget.organizationId,
            studentId: studentId,
            fraisId: fraisId,
            lang: LocaleController.instance.lang.code,
          );
      if (!mounted) return;
      final instructions =
          data["instructions"]?.toString() ?? l10n.parentPayComingSoon;
      messenger.showSnackBar(SnackBar(content: Text(instructions)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blueGrey.shade100),
      ),
      child: ListTile(
        leading: Icon(icon, color: EteyeloColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _PanelBody extends StatelessWidget {
  const _PanelBody({
    required this.panel,
    required this.data,
    required this.l10n,
    required this.onPayFee,
  });

  final String panel;
  final Map<String, dynamic> data;
  final L10n l10n;
  final void Function(String fraisId) onPayFee;

  @override
  Widget build(BuildContext context) {
    if (panel == "fees") {
      final fees = (data["fees"] as List?) ?? const [];
      final due = (data["totalDue"] as num?)?.toDouble() ?? 0;
      final paid = (data["totalPaid"] as num?)?.toDouble() ?? 0;
      final reste = (data["totalReste"] as num?)?.toDouble() ?? 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryRow(label: l10n.parentDue, value: due.toStringAsFixed(2)),
          _SummaryRow(label: l10n.parentPaid, value: paid.toStringAsFixed(2)),
          _SummaryRow(
            label: l10n.parentReste,
            value: reste.toStringAsFixed(2),
            emphasize: true,
          ),
          const SizedBox(height: 8),
          for (final raw in fees)
            if (raw is Map)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(raw["nameFrais"]?.toString() ?? "—"),
                subtitle: Text(
                  "${l10n.parentDue} ${(raw["due"] as num?)?.toStringAsFixed(2) ?? "0"} · "
                  "${l10n.parentPaid} ${(raw["paid"] as num?)?.toStringAsFixed(2) ?? "0"}",
                ),
                trailing: _feeTrailing(raw),
              ),
        ],
      );
    }

    if (panel == "grades") {
      final periods = (data["periods"] as List?) ?? const [];
      if (periods.isEmpty) {
        return Text(l10n.parentNoGrades);
      }
      return Column(
        children: [
          for (final raw in periods)
            if (raw is Map)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(raw["label"]?.toString() ?? "—"),
                trailing: Text(
                  "${raw["percent"] ?? raw["score"] ?? "—"} %",
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
        ],
      );
    }

    final periods = (data["periods"] as List?) ?? const [];
    final available = data["pdfAvailable"] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          available ? l10n.parentBulletinReady : l10n.parentBulletinSoon,
          style: TextStyle(color: Colors.blueGrey.shade700),
        ),
        const SizedBox(height: 8),
        for (final raw in periods)
          if (raw is Map)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(raw["label"]?.toString() ?? "—"),
              trailing: available
                  ? const Icon(Icons.download_outlined)
                  : const Icon(Icons.lock_outline, size: 18),
            ),
      ],
    );
  }

  Widget _feeTrailing(Map raw) {
    final fraisId = raw["fraisId"]?.toString();
    if (fraisId == null || fraisId.isEmpty) {
      return Text(
        ((raw["reste"] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
        style: const TextStyle(fontWeight: FontWeight.w700),
      );
    }
    return TextButton(
      onPressed: () => onPayFee(fraisId),
      child: Text(l10n.parentPay),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(
              fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
              color: emphasize ? EteyeloColors.primaryDark : null,
            ),
          ),
        ],
      ),
    );
  }
}
