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

enum _BotStep { idle, askClass, askName, loading }

enum _MsgKind { text, result, error }

class _ChatMsg {
  _ChatMsg.text({required this.mine, required this.text})
      : kind = _MsgKind.text,
        panel = null,
        panelData = null,
        studentId = null;

  _ChatMsg.result({
    required this.text,
    required this.panel,
    required this.panelData,
    required this.studentId,
  })  : mine = false,
        kind = _MsgKind.result;

  _ChatMsg.error(this.text)
      : mine = false,
        kind = _MsgKind.error,
        panel = null,
        panelData = null,
        studentId = null;

  final bool mine;
  final _MsgKind kind;
  final String text;
  final String? panel;
  final Map<String, dynamic>? panelData;
  final String? studentId;
}

/// Hub parent en mode chatbot (Telegram) : sujet → classe → élève → résultat.
class ParentHubScreen extends ConsumerStatefulWidget {
  const ParentHubScreen({super.key, required this.organizationId});

  final String organizationId;

  @override
  ConsumerState<ParentHubScreen> createState() => _ParentHubScreenState();
}

class _ParentHubScreenState extends ConsumerState<ParentHubScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  bool _booting = true;
  String? _bootError;
  List<Map<String, dynamic>> _children = [];
  final List<_ChatMsg> _messages = [];

  _BotStep _step = _BotStep.idle;
  String? _topic; // fees | grades | bulletin
  String? _className;
  Map<String, dynamic>? _student;
  List<String> _suggestions = [];

  L10n get _l10n => L10n.of(LocaleController.instance.lang);

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    setState(() {
      _booting = true;
      _bootError = null;
    });
    try {
      final items = await ref
          .read(parentRepositoryProvider)
          .listChildren(widget.organizationId);
      if (!mounted) return;
      setState(() {
        _children = items;
        _booting = false;
        if (items.isNotEmpty) {
          _messages.add(_ChatMsg.text(mine: false, text: _l10n.parentBotWelcome));
        }
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bootError = e.toString();
        _booting = false;
      });
    }
  }

  List<String> get _classes {
    final seen = <String>{};
    final out = <String>[];
    for (final c in _children) {
      final name = (c["className"]?.toString() ?? "").trim();
      if (name.isEmpty || !seen.add(name.toLowerCase())) continue;
      out.add(name);
    }
    out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  List<Map<String, dynamic>> _childrenInClass(String className) {
    final key = className.trim().toLowerCase();
    return _children
        .where((c) => (c["className"]?.toString() ?? "").trim().toLowerCase() == key)
        .toList();
  }

  String _topicLabel(String topic) => switch (topic) {
        "fees" => _l10n.parentFees,
        "grades" => _l10n.parentGrades,
        _ => _l10n.parentBulletin,
      };

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _pushBot(String text, {List<String>? suggestions}) {
    setState(() {
      _messages.add(_ChatMsg.text(mine: false, text: text));
      if (suggestions != null) _suggestions = suggestions;
    });
    _scrollToEnd();
  }

  void _pushUser(String text) {
    setState(() {
      _messages.add(_ChatMsg.text(mine: true, text: text));
    });
    _scrollToEnd();
  }

  void _resetFlow() {
    _step = _BotStep.idle;
    _topic = null;
    _className = null;
    _student = null;
    _suggestions = [];
  }

  Future<void> _startTopic(String topic) async {
    if (_step == _BotStep.loading) return;
    final label = _topicLabel(topic);
    _pushUser(label);
    setState(() {
      _topic = topic;
      _className = null;
      _student = null;
    });

    final classes = _classes;
    if (classes.isEmpty) {
      // Pas de classe renseignée : proposer directement les noms.
      await _askOrPickName(_children);
      return;
    }
    if (classes.length == 1) {
      await _selectClass(classes.first, silent: false);
      return;
    }
    setState(() {
      _step = _BotStep.askClass;
      _suggestions = classes;
    });
    _pushBot(_l10n.parentBotAskClass, suggestions: classes);
  }

  Future<void> _selectClass(String className, {bool silent = false}) async {
    if (!silent) _pushUser(className);
    setState(() => _className = className);
    final kids = _childrenInClass(className);
    if (kids.isEmpty) {
      _pushBot(_l10n.parentBotUnknownClass, suggestions: _classes);
      setState(() {
        _step = _BotStep.askClass;
        _suggestions = _classes;
      });
      return;
    }
    await _askOrPickName(kids);
  }

  Future<void> _askOrPickName(List<Map<String, dynamic>> kids) async {
    if (kids.length == 1) {
      await _selectStudent(kids.first, silent: kids.length == 1 && _children.length == 1);
      return;
    }
    final names = kids
        .map((c) => (c["fullName"]?.toString() ?? "").trim())
        .where((n) => n.isNotEmpty)
        .toList();
    setState(() {
      _step = _BotStep.askName;
      _suggestions = names;
    });
    _pushBot(_l10n.parentBotAskName, suggestions: names);
  }

  Future<void> _selectStudent(
    Map<String, dynamic> child, {
    bool silent = false,
  }) async {
    final name = (child["fullName"]?.toString() ?? "").trim();
    if (!silent && name.isNotEmpty) _pushUser(name);
    setState(() {
      _student = child;
      _suggestions = [];
      _step = _BotStep.loading;
    });
    _pushBot(_l10n.parentBotLoading);
    await _loadResult();
  }

  Future<void> _loadResult() async {
    final topic = _topic;
    final studentId = _student?["studentId"]?.toString();
    if (topic == null || studentId == null || studentId.isEmpty) {
      setState(_resetFlow);
      return;
    }
    try {
      final repo = ref.read(parentRepositoryProvider);
      final data = switch (topic) {
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
      final name = _student?["fullName"]?.toString() ?? "—";
      final classLabel = (_className ?? _student?["className"]?.toString() ?? "")
          .trim();
      final header = classLabel.isEmpty
          ? "${_l10n.parentBotResultFor} $name"
          : "${_l10n.parentBotResultFor} $name ($classLabel)";
      final resultStudentId = studentId;
      setState(() {
        // Retire le « Chargement… » précédent.
        if (_messages.isNotEmpty &&
            _messages.last.kind == _MsgKind.text &&
            !_messages.last.mine &&
            _messages.last.text == _l10n.parentBotLoading) {
          _messages.removeLast();
        }
        _messages.add(
          _ChatMsg.result(
            text: header,
            panel: topic,
            panelData: data,
            studentId: resultStudentId,
          ),
        );
        _resetFlow();
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_messages.isNotEmpty &&
            _messages.last.text == _l10n.parentBotLoading) {
          _messages.removeLast();
        }
        _messages.add(_ChatMsg.error(e.toString()));
        _resetFlow();
      });
      _scrollToEnd();
    }
  }

  String? _matchTopic(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.isEmpty) return null;
    if (t.contains("frais") ||
        t.contains("fee") ||
        t.contains("propina") ||
        t == "paiement" ||
        t == "payment") {
      return "fees";
    }
    if (t.contains("note") ||
        t.contains("grade") ||
        t.contains("moyenne") ||
        t.contains("période") ||
        t.contains("periode")) {
      return "grades";
    }
    if (t.contains("bulletin") ||
        t.contains("report") ||
        t.contains("boletim") ||
        t.contains("pdf")) {
      return "bulletin";
    }
    return null;
  }

  Map<String, dynamic>? _matchStudent(
    String raw,
    List<Map<String, dynamic>> pool,
  ) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return null;
    final exact = pool.where((c) {
      final n = (c["fullName"]?.toString() ?? "").trim().toLowerCase();
      return n == q;
    }).toList();
    if (exact.length == 1) return exact.first;
    final partial = pool.where((c) {
      final n = (c["fullName"]?.toString() ?? "").trim().toLowerCase();
      return n.contains(q) || q.contains(n);
    }).toList();
    if (partial.length == 1) return partial.first;
    return null;
  }

  String? _matchClass(String raw) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return null;
    final classes = _classes;
    for (final c in classes) {
      if (c.toLowerCase() == q) return c;
    }
    final partial = classes.where((c) => c.toLowerCase().contains(q)).toList();
    if (partial.length == 1) return partial.first;
    return null;
  }

  Future<void> _onSubmit() async {
    final text = _input.text.trim();
    if (text.isEmpty || _step == _BotStep.loading) return;
    _input.clear();

    switch (_step) {
      case _BotStep.idle:
        final topic = _matchTopic(text);
        if (topic != null) {
          await _startTopic(topic);
        } else {
          _pushUser(text);
          _pushBot(_l10n.parentBotWelcome);
        }
      case _BotStep.askClass:
        _pushUser(text);
        final matched = _matchClass(text);
        if (matched == null) {
          _pushBot(_l10n.parentBotUnknownClass, suggestions: _classes);
          setState(() => _suggestions = _classes);
          return;
        }
        await _selectClass(matched, silent: true);
      case _BotStep.askName:
        _pushUser(text);
        final pool = _className != null
            ? _childrenInClass(_className!)
            : _children;
        final matched = _matchStudent(text, pool);
        if (matched == null) {
          final names = pool
              .map((c) => (c["fullName"]?.toString() ?? "").trim())
              .where((n) => n.isNotEmpty)
              .toList();
          _pushBot(_l10n.parentBotUnknownName, suggestions: names);
          setState(() => _suggestions = names);
          return;
        }
        await _selectStudent(matched, silent: true);
      case _BotStep.loading:
        break;
    }
  }

  Future<void> _onSuggestionTap(String value) async {
    if (_step == _BotStep.askClass) {
      await _selectClass(value);
    } else if (_step == _BotStep.askName) {
      final pool = _className != null
          ? _childrenInClass(_className!)
          : _children;
      final matched = _matchStudent(value, pool);
      if (matched != null) await _selectStudent(matched);
    }
  }

  Future<void> _payFee(String studentId, String fraisId) async {
    if (studentId.isEmpty) return;
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
          data["instructions"]?.toString() ?? _l10n.parentPayComingSoon;
      messenger.showSnackBar(SnackBar(content: Text(instructions)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? EteyeloColors.chatBackgroundDark
        : EteyeloColors.chatBackground;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(l10n.parentHubTitle),
      ),
      body: _booting
          ? const Center(child: CircularProgressIndicator())
          : _bootError != null && _children.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_bootError!, textAlign: TextAlign.center),
                  ),
                )
              : _children.isEmpty
                  ? Center(child: Text(l10n.parentNoChildren))
                  : Column(
                      children: [
                        Expanded(
                          child: ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                            itemCount: _messages.length,
                            itemBuilder: (context, i) {
                              final msg = _messages[i];
                              return _Bubble(
                                msg: msg,
                                l10n: l10n,
                                isDark: isDark,
                                onPayFee: (fraisId) {
                                  final sid = msg.studentId;
                                  if (sid == null) return;
                                  unawaited(_payFee(sid, fraisId));
                                },
                              );
                            },
                          ),
                        ),
                        if (_suggestions.isNotEmpty &&
                            (_step == _BotStep.askClass ||
                                _step == _BotStep.askName))
                          _SuggestionStrip(
                            items: _suggestions,
                            onTap: (v) => unawaited(_onSuggestionTap(v)),
                            isDark: isDark,
                          ),
                        _TopicList(
                          l10n: l10n,
                          enabled: _step != _BotStep.loading,
                          onTap: (topic) => unawaited(_startTopic(topic)),
                          isDark: isDark,
                        ),
                        _ComposerBar(
                          controller: _input,
                          focusNode: _focus,
                          hint: _step == _BotStep.idle
                              ? l10n.parentBotHintIdle
                              : l10n.parentBotHint,
                          enabled: _step != _BotStep.loading,
                          onSend: () => unawaited(_onSubmit()),
                          isDark: isDark,
                        ),
                      ],
                    ),
    );
  }
}

// ── UI pieces ───────────────────────────────────────────────────────────────

class _TopicList extends StatelessWidget {
  const _TopicList({
    required this.l10n,
    required this.enabled,
    required this.onTap,
    required this.isDark,
  });

  final L10n l10n;
  final bool enabled;
  final void Function(String topic) onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bar = isDark
        ? EteyeloColors.chatInputBarDark
        : EteyeloColors.chatInputBar;
    final border = isDark
        ? EteyeloColors.listDividerDark
        : EteyeloColors.listDivider;

    Widget tile({
      required IconData icon,
      required String title,
      required String topic,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? () => onTap(topic) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 22, color: EteyeloColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: enabled
                          ? (isDark
                              ? EteyeloColors.bubbleIncomingTextDark
                              : EteyeloColors.bubbleIncomingText)
                          : EteyeloColors.bubbleMeta,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: EteyeloColors.bubbleMeta,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bar,
        border: Border(top: BorderSide(color: border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tile(
            icon: Icons.payments_outlined,
            title: l10n.parentFees,
            topic: "fees",
          ),
          Divider(height: 1, color: border),
          tile(
            icon: Icons.school_outlined,
            title: l10n.parentGrades,
            topic: "grades",
          ),
          Divider(height: 1, color: border),
          tile(
            icon: Icons.picture_as_pdf_outlined,
            title: l10n.parentBulletin,
            topic: "bulletin",
          ),
        ],
      ),
    );
  }
}

class _SuggestionStrip extends StatelessWidget {
  const _SuggestionStrip({
    required this.items,
    required this.onTap,
    required this.isDark,
  });

  final List<String> items;
  final void Function(String) onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bar = isDark
        ? EteyeloColors.chatInputBarDark
        : EteyeloColors.chatInputBar;
    return Container(
      width: double.infinity,
      color: bar,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final item in items) ...[
              ActionChip(
                label: Text(item),
                onPressed: () => onTap(item),
                backgroundColor: isDark
                    ? EteyeloColors.bubbleIncomingDark
                    : Colors.white,
                side: BorderSide(
                  color: EteyeloColors.primary.withValues(alpha: 0.35),
                ),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: EteyeloColors.primaryDark,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.enabled,
    required this.onSend,
    required this.isDark,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool enabled;
  final VoidCallback onSend;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bar = isDark
        ? EteyeloColors.chatInputBarDark
        : EteyeloColors.chatInputBar;
    return SafeArea(
      top: false,
      child: Container(
        color: bar,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isDark
                      ? EteyeloColors.bubbleIncomingDark
                      : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: enabled,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 1,
                  maxLines: 4,
                  cursorColor: EteyeloColors.primary,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(
                      color: EteyeloColors.bubbleMeta,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: enabled ? (_) => onSend() : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: enabled
                  ? EteyeloColors.primaryDark
                  : EteyeloColors.bubbleMeta,
              shape: const CircleBorder(),
              elevation: 1,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? onSend : null,
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.send_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.msg,
    required this.l10n,
    required this.isDark,
    required this.onPayFee,
  });

  final _ChatMsg msg;
  final L10n l10n;
  final bool isDark;
  final void Function(String fraisId) onPayFee;

  @override
  Widget build(BuildContext context) {
    final mine = msg.mine;
    final bg = mine
        ? (isDark
            ? EteyeloColors.bubbleOutgoingDark
            : EteyeloColors.bubbleOutgoing)
        : (isDark
            ? EteyeloColors.bubbleIncomingDark
            : EteyeloColors.bubbleIncoming);
    final fg = mine
        ? (isDark
            ? EteyeloColors.bubbleOutgoingTextDark
            : EteyeloColors.bubbleOutgoingText)
        : (isDark
            ? EteyeloColors.bubbleIncomingTextDark
            : EteyeloColors.bubbleIncomingText);
    final border = mine
        ? (isDark
            ? EteyeloColors.bubbleOutgoingBorderDark
            : EteyeloColors.bubbleOutgoingBorder)
        : (isDark
            ? EteyeloColors.bubbleIncomingBorderDark
            : EteyeloColors.bubbleIncomingBorder);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.86,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(mine ? 14 : 4),
              bottomRight: Radius.circular(mine ? 4 : 14),
            ),
            border: Border.all(color: border),
          ),
          child: msg.kind == _MsgKind.result &&
                  msg.panel != null &&
                  msg.panelData != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      msg.text,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: fg,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _PanelBody(
                      panel: msg.panel!,
                      data: msg.panelData!,
                      l10n: l10n,
                      onPayFee: onPayFee,
                    ),
                  ],
                )
              : Text(
                  msg.text,
                  style: TextStyle(
                    color: msg.kind == _MsgKind.error
                        ? const Color(0xFFB91C1C)
                        : fg,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
        ),
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
                dense: true,
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
          style: TextStyle(color: Colors.blueGrey.shade700, fontSize: 13),
        ),
        const SizedBox(height: 8),
        for (final raw in periods)
          if (raw is Map)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
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
