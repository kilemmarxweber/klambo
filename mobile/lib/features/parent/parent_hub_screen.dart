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

enum _BotStep { idle, askClass, askName, askTopic, askDetail, loading }

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

/// Hub parent en mode chatbot : sujet ↔ classe ↔ élève (multi-classes OK).
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
  /// Libellé chip → élève (ex. « Marie Dupont · 6ème A »).
  final Map<String, Map<String, dynamic>> _studentByLabel = {};
  /// Réponse API complète avant filtre frais / période.
  Map<String, dynamic>? _rawData;
  /// Libellé chip → entrée frais ou période (ou marqueur « tout »).
  final Map<String, Map<String, dynamic>> _detailByLabel = {};
  static const _allDetailId = "__all__";

  L10n get _l10n => L10n.of(LocaleController.instance.lang);

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  @override
  void dispose() {
    _wipeChat();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Pas de persistance : tout est effacé en quittant l’espace parent.
  void _wipeChat() {
    _messages.clear();
    _rawData = null;
    _detailByLabel.clear();
    _studentByLabel.clear();
    _suggestions = [];
    _step = _BotStep.idle;
    _topic = null;
    _className = null;
    _student = null;
    _input.clear();
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
        .where(
          (c) =>
              (c["className"]?.toString() ?? "").trim().toLowerCase() == key,
        )
        .toList();
  }

  bool _poolSpansClasses(List<Map<String, dynamic>> pool) {
    final seen = <String>{};
    for (final c in pool) {
      final name = (c["className"]?.toString() ?? "").trim().toLowerCase();
      if (name.isEmpty) continue;
      seen.add(name);
      if (seen.length > 1) return true;
    }
    return false;
  }

  String _fullName(Map<String, dynamic> child) =>
      (child["fullName"]?.toString() ?? "").trim();

  String _classOf(Map<String, dynamic> child) =>
      (child["className"]?.toString() ?? "").trim();

  /// Nom + classe si plusieurs classes (évite l’ambiguïté entre frères/sœurs).
  String _childLabel(
    Map<String, dynamic> child, {
    List<Map<String, dynamic>>? pool,
  }) {
    final name = _fullName(child);
    final cls = _classOf(child);
    final showClass = cls.isNotEmpty &&
        (_classes.length > 1 ||
            (pool != null && _poolSpansClasses(pool)));
    return showClass ? "$name · $cls" : name;
  }

  List<String> _nameLabels(List<Map<String, dynamic>> kids) {
    _studentByLabel.clear();
    final labels = <String>[];
    for (final c in kids) {
      final name = _fullName(c);
      if (name.isEmpty) continue;
      final label = _childLabel(c, pool: kids);
      // Collision rare : suffixe studentId court.
      var unique = label;
      if (_studentByLabel.containsKey(unique)) {
        final id = c["studentId"]?.toString() ?? "";
        unique = id.length >= 4 ? "$label (${id.substring(0, 4)})" : "$label ·";
      }
      _studentByLabel[unique] = c;
      labels.add(unique);
    }
    return labels;
  }

  String _topicLabel(String topic) => switch (topic) {
        "fees" => _l10n.parentFees,
        "grades" => _l10n.parentGrades,
        _ => _l10n.parentBulletin,
      };

  List<String> get _topicSuggestions => [
        _l10n.parentFees,
        _l10n.parentGrades,
        _l10n.parentBulletin,
      ];

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
    _studentByLabel.clear();
    _rawData = null;
    _detailByLabel.clear();
  }

  void _removeTrailingLoading() {
    if (_messages.isNotEmpty &&
        _messages.last.kind == _MsgKind.text &&
        !_messages.last.mine &&
        _messages.last.text == _l10n.parentBotLoading) {
      _messages.removeLast();
    }
  }

  String _feeItemLabel(Map raw) {
    final name = (raw["nameFrais"] ??
            raw["typeFrais"] ??
            raw["type"] ??
            raw["category"] ??
            raw["label"] ??
            raw["name"])
        ?.toString()
        .trim();
    return (name == null || name.isEmpty) ? "—" : name;
  }

  String _periodItemLabel(Map raw) {
    final name = (raw["label"] ??
            raw["periodLabel"] ??
            raw["name"] ??
            raw["periodName"])
        ?.toString()
        .trim();
    return (name == null || name.isEmpty) ? "—" : name;
  }

  List<Map<String, dynamic>> _feeItems(Map<String, dynamic> data) {
    final fees = (data["fees"] as List?) ?? const [];
    return fees
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<Map<String, dynamic>> _periodItems(Map<String, dynamic> data) {
    final periods = (data["periods"] as List?) ?? const [];
    return periods
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Options distinctes à proposer (types de frais ou périodes).
  List<Map<String, dynamic>> _detailOptions(
    String topic,
    Map<String, dynamic> data,
  ) {
    if (topic == "fees") {
      final seen = <String>{};
      final out = <Map<String, dynamic>>[];
      for (final f in _feeItems(data)) {
        final label = _feeItemLabel(f);
        if (!seen.add(label.toLowerCase())) continue;
        out.add(f);
      }
      return out;
    }
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final p in _periodItems(data)) {
      final label = _periodItemLabel(p);
      if (!seen.add(label.toLowerCase())) continue;
      out.add(p);
    }
    return out;
  }

  List<String> _buildDetailSuggestions(
    String topic,
    List<Map<String, dynamic>> options,
  ) {
    _detailByLabel.clear();
    final labels = <String>[];
    if (options.length > 1) {
      final all = _l10n.parentBotShowAll;
      _detailByLabel[all] = {_allDetailId: true};
      labels.add(all);
    }
    for (final item in options) {
      final base =
          topic == "fees" ? _feeItemLabel(item) : _periodItemLabel(item);
      var unique = base;
      var n = 2;
      while (_detailByLabel.containsKey(unique)) {
        unique = "$base ($n)";
        n++;
      }
      _detailByLabel[unique] = item;
      labels.add(unique);
    }
    return labels;
  }

  Map<String, dynamic> _filterPanelData({
    required String topic,
    required Map<String, dynamic> raw,
    required Map<String, dynamic>? choice,
  }) {
    if (choice == null || choice[_allDetailId] == true) {
      return Map<String, dynamic>.from(raw);
    }
    if (topic == "fees") {
      final want = _feeItemLabel(choice).toLowerCase();
      final fees = _feeItems(raw)
          .where((f) => _feeItemLabel(f).toLowerCase() == want)
          .toList();
      var due = 0.0;
      var paid = 0.0;
      var reste = 0.0;
      for (final f in fees) {
        due += (f["due"] as num?)?.toDouble() ?? 0;
        paid += (f["paid"] as num?)?.toDouble() ?? 0;
        reste += (f["reste"] as num?)?.toDouble() ?? 0;
      }
      return {
        ...raw,
        "fees": fees,
        "totalDue": due,
        "totalPaid": paid,
        "totalReste": reste,
      };
    }
    final want = _periodItemLabel(choice).toLowerCase();
    final periods = _periodItems(raw)
        .where((p) => _periodItemLabel(p).toLowerCase() == want)
        .toList();
    return {
      ...raw,
      "periods": periods,
    };
  }

  /// Démarre ou complète un sujet (conserve élève/classe déjà choisis).
  Future<void> _startTopic(String topic, {bool echoUser = true}) async {
    if (_step == _BotStep.loading) return;
    if (echoUser) _pushUser(_topicLabel(topic));
    setState(() => _topic = topic);

    if (_student != null) {
      await _continueAfterStudent();
      return;
    }

    if (_className != null) {
      await _askOrPickName(_childrenInClass(_className!));
      return;
    }

    final classes = _classes;
    if (classes.isEmpty) {
      await _askOrPickName(_children);
      return;
    }
    if (classes.length == 1) {
      await _selectClass(classes.first, silent: _children.length == 1);
      return;
    }
    setState(() {
      _step = _BotStep.askClass;
      _suggestions = classes;
      _studentByLabel.clear();
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
    // Élève déjà choisi ailleurs : vérifier qu'il est dans cette classe.
    final current = _student;
    if (current != null) {
      final sid = current["studentId"]?.toString();
      final inClass = kids.any((c) => c["studentId"]?.toString() == sid);
      if (inClass) {
        await _continueAfterStudent();
        return;
      }
    }
    await _askOrPickName(kids);
  }

  Future<void> _askOrPickName(List<Map<String, dynamic>> kids) async {
    if (kids.length == 1) {
      final only = kids.first;
      final silent = _children.length == 1;
      await _selectStudent(only, silent: silent, confirmLabel: !silent);
      return;
    }
    final labels = _nameLabels(kids);
    setState(() {
      _step = _BotStep.askName;
      _suggestions = labels;
    });
    _pushBot(_l10n.parentBotAskName, suggestions: labels);
  }

  Future<void> _askTopic() async {
    setState(() {
      _step = _BotStep.askTopic;
      // Pas de chips : la _TopicList verticale suffit.
      _suggestions = [];
      _studentByLabel.clear();
    });
    _pushBot(_l10n.parentBotAskTopic);
  }

  Future<void> _continueAfterStudent() async {
    if (_topic != null) {
      await _fetchThenAskDetail();
      return;
    }
    await _askTopic();
  }

  Future<void> _selectStudent(
    Map<String, dynamic> child, {
    bool silent = false,
    bool confirmLabel = false,
  }) async {
    final label = _childLabel(child);
    if (!silent) {
      _pushUser(_fullName(child).isNotEmpty ? _fullName(child) : label);
    } else if (confirmLabel && label.isNotEmpty) {
      _pushBot("${_l10n.parentBotPickedStudent} : $label");
    }
    setState(() {
      _student = child;
      final cls = _classOf(child);
      if (cls.isNotEmpty) _className = cls;
      _suggestions = [];
      _studentByLabel.clear();
    });
    await _continueAfterStudent();
  }

  /// Propose les vrais noms quand le parent tape un prénom (partiel).
  Future<void> _handleNameQuery(
    String typed, {
    required List<Map<String, dynamic>> pool,
    bool alreadyEchoed = false,
  }) async {
    if (!alreadyEchoed) _pushUser(typed);
    final matches = _findStudents(typed, pool: pool);
    if (matches.isEmpty) {
      final labels = _nameLabels(pool);
      _pushBot(_l10n.parentBotUnknownName, suggestions: labels);
      setState(() {
        _step = _BotStep.askName;
        _suggestions = labels;
      });
      return;
    }
    if (matches.length == 1) {
      final only = matches.first;
      final real = _childLabel(only, pool: pool);
      _pushBot("${_l10n.parentBotPickedStudent} : $real");
      await _selectStudent(only, silent: true);
      return;
    }
    final labels = _nameLabels(matches);
    setState(() {
      _step = _BotStep.askName;
      _suggestions = labels;
    });
    _pushBot(_l10n.parentBotNameMatches, suggestions: labels);
  }

  /// Charge les données puis propose type de frais / période si besoin.
  Future<void> _fetchThenAskDetail() async {
    final topic = _topic;
    final studentId = _student?["studentId"]?.toString();
    if (topic == null || studentId == null || studentId.isEmpty) {
      setState(_resetFlow);
      return;
    }
    setState(() {
      _suggestions = [];
      _step = _BotStep.loading;
      _rawData = null;
      _detailByLabel.clear();
    });
    _pushBot(_l10n.parentBotLoading);
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
      setState(() {
        _removeTrailingLoading();
        _rawData = data;
      });

      final options = _detailOptions(topic, data);
      // Plusieurs choix → le parent précise ce qui s'affiche.
      if (options.length > 1) {
        final labels = _buildDetailSuggestions(topic, options);
        setState(() {
          _step = _BotStep.askDetail;
          _suggestions = labels;
        });
        _pushBot(
          topic == "fees"
              ? _l10n.parentBotAskFeeType
              : _l10n.parentBotAskPeriod,
          suggestions: labels,
        );
        return;
      }
      // 0 ou 1 option : affichage direct (déjà précis).
      await _presentResult(
        choice: options.isEmpty ? null : options.first,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _removeTrailingLoading();
        _messages.add(_ChatMsg.error(e.toString()));
        _resetFlow();
      });
      _scrollToEnd();
    }
  }

  Future<void> _selectDetail(String label, {bool silent = false}) async {
    final choice = _detailByLabel[label.trim()];
    if (choice == null) {
      final fallback = _suggestions;
      _pushBot(_l10n.parentBotUnknownDetail, suggestions: fallback);
      setState(() {
        _step = _BotStep.askDetail;
        _suggestions = fallback;
      });
      return;
    }
    if (!silent) _pushUser(label);
    await _presentResult(choice: choice);
  }

  Future<void> _presentResult({
    required Map<String, dynamic>? choice,
  }) async {
    final topic = _topic;
    final raw = _rawData;
    final studentId = _student?["studentId"]?.toString();
    if (topic == null || raw == null || studentId == null) {
      setState(_resetFlow);
      return;
    }

    var panelData = _filterPanelData(
      topic: topic,
      raw: raw,
      choice: choice,
    );

    // Bulletin : recharger la méta de la période choisie si periodId dispo.
    if (topic == "bulletin" &&
        choice != null &&
        choice[_allDetailId] != true) {
      final periodId = choice["periodId"];
      final id = periodId is int
          ? periodId
          : int.tryParse(periodId?.toString() ?? "");
      if (id != null) {
        try {
          panelData = await ref.read(parentRepositoryProvider).bulletinMeta(
                organizationId: widget.organizationId,
                studentId: studentId,
                periodId: id,
              );
        } catch (_) {
          // Garde le filtre local si le rechargement échoue.
        }
      }
    }

    if (!mounted) return;
    final name = _fullName(_student!);
    final classLabel = (_className ?? _classOf(_student!)).trim();
    var header = classLabel.isEmpty
        ? "${_l10n.parentBotResultFor} $name"
        : "${_l10n.parentBotResultFor} $name ($classLabel)";
    if (choice != null && choice[_allDetailId] != true) {
      final detail = topic == "fees"
          ? _feeItemLabel(choice)
          : _periodItemLabel(choice);
      if (detail.isNotEmpty && detail != "—") {
        header = "$header — $detail";
      }
    }

    setState(() {
      _messages.add(
        _ChatMsg.result(
          text: header,
          panel: topic,
          panelData: panelData,
          studentId: studentId,
        ),
      );
      _resetFlow();
    });
    _scrollToEnd();
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

  /// Prénom / nom partiel → tous les élèves correspondants (pas seulement 1).
  List<Map<String, dynamic>> _findStudents(
    String raw, {
    required List<Map<String, dynamic>> pool,
  }) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) return const [];

    // Si le chip contient « · classe », matcher sur le nom seul.
    final beforeDot = q.split("·").first.trim();
    final query = beforeDot.isNotEmpty ? beforeDot : q;

    int score(Map<String, dynamic> c) {
      final full = _fullName(c).toLowerCase();
      if (full.isEmpty) return 0;
      if (full == query) return 100;
      final tokens = full.split(RegExp(r"\s+")).where((t) => t.isNotEmpty);
      for (final t in tokens) {
        if (t == query) return 90; // prénom exact
        if (t.startsWith(query)) return 80;
      }
      if (full.startsWith(query)) return 70;
      if (full.contains(query)) return 50;
      if (query.contains(full) && full.length >= 3) return 40;
      return 0;
    }

    final ranked = <(int, Map<String, dynamic>)>[];
    final seen = <String>{};
    for (final c in pool) {
      final s = score(c);
      if (s <= 0) continue;
      final id = c["studentId"]?.toString() ?? _fullName(c);
      if (!seen.add(id)) continue;
      ranked.add((s, c));
    }
    ranked.sort((a, b) => b.$1.compareTo(a.$1));
    return ranked.map((e) => e.$2).toList();
  }

  Map<String, dynamic>? _matchStudentExactLabel(String raw) {
    final key = raw.trim();
    return _studentByLabel[key];
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
          return;
        }
        final nameHits = _findStudents(text, pool: _children);
        if (nameHits.isNotEmpty) {
          await _handleNameQuery(text, pool: _children);
          return;
        }
        final classHit = _matchClass(text);
        if (classHit != null) {
          _pushUser(text);
          setState(() {
            _topic = null;
            _student = null;
          });
          await _selectClass(classHit, silent: true);
          // Après classe sans sujet : demander l'élève puis le sujet.
          return;
        }
        _pushUser(text);
        _pushBot(_l10n.parentBotWelcome);
      case _BotStep.askClass:
        _pushUser(text);
        final topic = _matchTopic(text);
        if (topic != null) {
          setState(() => _topic = topic);
          // Reposer la question classe.
          _pushBot(_l10n.parentBotAskClass, suggestions: _classes);
          setState(() {
            _step = _BotStep.askClass;
            _suggestions = _classes;
          });
          return;
        }
        final matched = _matchClass(text);
        if (matched == null) {
          _pushBot(_l10n.parentBotUnknownClass, suggestions: _classes);
          setState(() => _suggestions = _classes);
          return;
        }
        await _selectClass(matched, silent: true);
      case _BotStep.askName:
        final fromChip = _matchStudentExactLabel(text);
        if (fromChip != null) {
          _pushUser(text);
          await _selectStudent(fromChip, silent: true);
          return;
        }
        final topic = _matchTopic(text);
        if (topic != null) {
          _pushUser(text);
          setState(() => _topic = topic);
          final pool = _className != null
              ? _childrenInClass(_className!)
              : _children;
          final labels = _nameLabels(pool);
          _pushBot(_l10n.parentBotAskName, suggestions: labels);
          setState(() {
            _step = _BotStep.askName;
            _suggestions = labels;
          });
          return;
        }
        final pool = _className != null
            ? _childrenInClass(_className!)
            : _children;
        await _handleNameQuery(text, pool: pool);
      case _BotStep.askTopic:
        final topic = _matchTopic(text);
        if (topic == null) {
          _pushUser(text);
          _pushBot(_l10n.parentBotAskTopic);
          setState(() {
            _step = _BotStep.askTopic;
            _suggestions = [];
          });
          return;
        }
        await _startTopic(topic);
      case _BotStep.askDetail:
        final key = _matchDetailLabel(text);
        if (key == null) {
          _pushUser(text);
          _pushBot(
            _l10n.parentBotUnknownDetail,
            suggestions: _suggestions,
          );
          setState(() => _step = _BotStep.askDetail);
          return;
        }
        await _selectDetail(key);
      case _BotStep.loading:
        break;
    }
  }

  String? _matchDetailLabel(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (_detailByLabel.containsKey(t)) return t;
    final lower = t.toLowerCase();
    for (final k in _detailByLabel.keys) {
      if (k.toLowerCase() == lower) return k;
    }
    final partial = _detailByLabel.keys
        .where(
          (k) =>
              k.toLowerCase().contains(lower) ||
              lower.contains(k.toLowerCase()),
        )
        .toList();
    if (partial.length == 1) return partial.first;
    return null;
  }

  Future<void> _onSuggestionTap(String value) async {
    switch (_step) {
      case _BotStep.askClass:
        await _selectClass(value);
      case _BotStep.askName:
        final fromChip = _matchStudentExactLabel(value);
        if (fromChip != null) {
          await _selectStudent(fromChip);
          return;
        }
        final pool = _className != null
            ? _childrenInClass(_className!)
            : _children;
        final hits = _findStudents(value, pool: pool);
        if (hits.length == 1) {
          await _selectStudent(hits.first);
        } else if (hits.isNotEmpty) {
          await _handleNameQuery(value, pool: pool);
        }
      case _BotStep.askTopic:
        final topic = _matchTopic(value);
        if (topic != null) await _startTopic(topic);
      case _BotStep.askDetail:
        await _selectDetail(value);
      case _BotStep.idle:
      case _BotStep.loading:
        break;
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

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _wipeChat();
      },
      child: Scaffold(
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
                              padding:
                                  const EdgeInsets.fromLTRB(12, 12, 12, 8),
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
                                  _step == _BotStep.askName ||
                                  _step == _BotStep.askDetail))
                            _SuggestionStrip(
                              items: _suggestions,
                              onTap: (v) => unawaited(_onSuggestionTap(v)),
                              isDark: isDark,
                              // Frais / périodes : icône à gauche pour gagner de la place.
                              leadingIcon: _step == _BotStep.askDetail
                                  ? (_topic == "fees"
                                      ? Icons.payments_outlined
                                      : Icons.date_range_outlined)
                                  : null,
                            ),
                          // Une seule liste (verticale + icônes) pour Frais / Notes / Bulletin.
                          if (_step == _BotStep.idle ||
                              _step == _BotStep.askTopic)
                            _TopicList(
                              l10n: l10n,
                              enabled: _step != _BotStep.loading,
                              onTap: (topic) => unawaited(_startTopic(topic)),
                              isDark: isDark,
                            ),
                          _ComposerBar(
                            controller: _input,
                            focusNode: _focus,
                            hint: switch (_step) {
                              _BotStep.askTopic => l10n.parentBotAskTopic,
                              _BotStep.askDetail => _topic == "fees"
                                  ? l10n.parentBotAskFeeType
                                  : l10n.parentBotAskPeriod,
                              _BotStep.idle => l10n.parentBotHintIdle,
                              _ => l10n.parentBotHint,
                            },
                            enabled: _step != _BotStep.loading,
                            onSend: () => unawaited(_onSubmit()),
                            isDark: isDark,
                          ),
                        ],
                      ),
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
    this.leadingIcon,
  });

  final List<String> items;
  final void Function(String) onTap;
  final bool isDark;
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final bar = isDark
        ? EteyeloColors.chatInputBarDark
        : EteyeloColors.chatInputBar;
    final border = isDark
        ? EteyeloColors.listDividerDark
        : EteyeloColors.listDivider;
    final textColor = isDark
        ? EteyeloColors.bubbleIncomingTextDark
        : EteyeloColors.bubbleIncomingText;

    // Liste verticale + icône (frais / période) : plus compact que les chips.
    if (leadingIcon != null) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: bar,
          border: Border(top: BorderSide(color: border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) Divider(height: 1, color: border),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onTap(items[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          leadingIcon,
                          size: 22,
                          color: EteyeloColors.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            items[i],
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: textColor,
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
              ),
            ],
          ],
        ),
      );
    }

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
