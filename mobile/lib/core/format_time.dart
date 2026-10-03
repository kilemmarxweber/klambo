String formatMessageTime(String? iso, {String yesterdayLabel = "Hier"}) {
  if (iso == null || iso.isEmpty) return "";
  final date = DateTime.tryParse(iso);
  if (date == null) return "";
  return formatClockDay(date, yesterdayLabel: yesterdayLabel);
}

String formatClockDay(DateTime date, {String yesterdayLabel = "Hier"}) {
  final local = date.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final msgDay = DateTime(local.year, local.month, local.day);
  final diff = today.difference(msgDay).inDays;

  final h = local.hour.toString().padLeft(2, "0");
  final m = local.minute.toString().padLeft(2, "0");
  if (diff == 0) return "$h:$m";
  if (diff == 1) return yesterdayLabel;
  if (diff < 7) {
    const days = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"];
    return days[local.weekday - 1];
  }
  return "${local.day.toString().padLeft(2, "0")}/${local.month.toString().padLeft(2, "0")}/${local.year}";
}

String formatClock(DateTime date) {
  final local = date.toLocal();
  final h = local.hour.toString().padLeft(2, "0");
  final m = local.minute.toString().padLeft(2, "0");
  return "$h:$m";
}
