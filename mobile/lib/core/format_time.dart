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

/// Jour civil local (année-mois-jour) pour comparer deux messages.
DateTime? messageCalendarDay(String? iso) {
  final date = DateTime.tryParse(iso ?? "");
  if (date == null) return null;
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool sameCalendarDay(String? isoA, String? isoB) {
  final a = messageCalendarDay(isoA);
  final b = messageCalendarDay(isoB);
  if (a == null || b == null) return false;
  return a == b;
}

/// Pastille de rupture de fil : « Aujourd'hui », « Hier », jour de semaine,
/// ou date longue (« 10 janvier 2026 »).
String formatChatDaySeparator(
  DateTime date, {
  String todayLabel = "Aujourd'hui",
  String yesterdayLabel = "Hier",
  String locale = "fr",
}) {
  final local = date.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;

  if (diff == 0) return todayLabel;
  if (diff == 1) return yesterdayLabel;

  // Cette semaine (hors hier) : nom du jour — plus lisible qu'une date pleine.
  if (diff > 1 && diff < 7) {
    return _weekdayLong(local.weekday, locale);
  }

  final month = _monthLong(local.month, locale);
  if (day.year == today.year) {
    return "${local.day} $month";
  }
  return "${local.day} $month ${local.year}";
}

String formatChatDaySeparatorIso(
  String? iso, {
  String todayLabel = "Aujourd'hui",
  String yesterdayLabel = "Hier",
  String locale = "fr",
}) {
  final date = DateTime.tryParse(iso ?? "");
  if (date == null) return "";
  return formatChatDaySeparator(
    date,
    todayLabel: todayLabel,
    yesterdayLabel: yesterdayLabel,
    locale: locale,
  );
}

String _weekdayLong(int weekday, String locale) {
  const fr = [
    "Lundi",
    "Mardi",
    "Mercredi",
    "Jeudi",
    "Vendredi",
    "Samedi",
    "Dimanche",
  ];
  const en = [
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday",
  ];
  const pt = [
    "Segunda-feira",
    "Terça-feira",
    "Quarta-feira",
    "Quinta-feira",
    "Sexta-feira",
    "Sábado",
    "Domingo",
  ];
  final list = switch (locale) {
    "en" => en,
    "pt" => pt,
    _ => fr,
  };
  return list[(weekday - 1).clamp(0, 6)];
}

String _monthLong(int month, String locale) {
  const fr = [
    "janvier",
    "février",
    "mars",
    "avril",
    "mai",
    "juin",
    "juillet",
    "août",
    "septembre",
    "octobre",
    "novembre",
    "décembre",
  ];
  const en = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];
  const pt = [
    "janeiro",
    "fevereiro",
    "março",
    "abril",
    "maio",
    "junho",
    "julho",
    "agosto",
    "setembro",
    "outubro",
    "novembro",
    "dezembro",
  ];
  final list = switch (locale) {
    "en" => en,
    "pt" => pt,
    _ => fr,
  };
  return list[(month - 1).clamp(0, 11)];
}
