import "dart:convert";

const _kPrefix = "__SATISFACTION__:";

class SatisfactionItem {
  const SatisfactionItem({
    required this.parentId,
    required this.branchId,
    required this.branchName,
    required this.schoolYearId,
    required this.children,
    required this.status,
    this.rating,
  });

  final String parentId;
  final String branchId;
  final String branchName;
  final String schoolYearId;
  final List<String> children;
  final String status;
  final int? rating;

  bool get isDone => status == "done";
}

class SatisfactionTrace {
  const SatisfactionTrace({
    required this.month,
    required this.year,
    required this.label,
    required this.items,
  });

  final int month;
  final int year;
  final String label;
  final List<SatisfactionItem> items;

  int get pendingCount => items.where((row) => !row.isDone).length;

  String get preview {
    if (pendingCount > 0) {
      return "Avis du mois à compléter · $pendingCount";
    }
    if (items.isNotEmpty) {
      return "Avis du mois validé";
    }
    return "Avis parent mensuel";
  }

  static SatisfactionTrace? tryParse(String? body) {
    if (body == null) return null;
    final trimmed = body.trim();
    if (!trimmed.startsWith(_kPrefix)) return null;
    try {
      final raw = jsonDecode(trimmed.substring(_kPrefix.length));
      if (raw is! Map) return null;
      final map = Map<String, dynamic>.from(raw);
      final itemsRaw = (map["items"] as List?) ?? const [];
      final items = itemsRaw
          .whereType<Map>()
          .map((item) {
            final data = Map<String, dynamic>.from(item);
            final childrenRaw = (data["children"] as List?) ?? const [];
            return SatisfactionItem(
              parentId: data["parentId"]?.toString() ?? "",
              branchId: data["branchId"]?.toString() ?? "",
              branchName: data["branchName"]?.toString() ?? "Établissement",
              schoolYearId: data["schoolYearId"]?.toString() ?? "",
              children: childrenRaw
                  .map((e) => e?.toString() ?? "")
                  .where((e) => e.isNotEmpty)
                  .toList(),
              status: data["status"]?.toString() ?? "pending",
              rating: (data["rating"] as num?)?.toInt(),
            );
          })
          .toList();
      return SatisfactionTrace(
        month: (map["month"] as num?)?.toInt() ?? 0,
        year: (map["year"] as num?)?.toInt() ?? 0,
        label: map["label"]?.toString() ?? "",
        items: items,
      );
    } catch (_) {
      return null;
    }
  }
}
