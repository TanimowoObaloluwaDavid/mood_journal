/// Day-bucketing helpers.
///
/// Every date here is **local** time. All bucketing goes through [startOfDay] so
/// that "Tuesday's entry" means the same thing across DST transitions and across
/// a device changing timezone.
library;

DateTime startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime startOfToday() => startOfDay(DateTime.now());

/// Midnight local on the first day of the month [offsetMonths] from [from].
DateTime startOfMonth(DateTime from, {int offsetMonths = 0}) =>
    DateTime(from.year, from.month + offsetMonths, 1);

/// Whole days between two dates, ignoring time-of-day.
///
/// Uses UTC normalisation so a DST boundary cannot produce 0.958 or 1.04 days.
int daysBetween(DateTime a, DateTime b) {
  final ua = DateTime.utc(a.year, a.month, a.day);
  final ub = DateTime.utc(b.year, b.month, b.day);
  return ub.difference(ua).inDays;
}

/// Inclusive list of days from [start] to [end].
Iterable<DateTime> daysInRange(DateTime start, DateTime end) sync* {
  var cursor = startOfDay(start);
  final last = startOfDay(end);
  while (!cursor.isAfter(last)) {
    yield cursor;
    cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
  }
}

/// Words in a body of text. Whitespace-only input is 0 words, never 1.
int countWords(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 0;
  return trimmed.split(RegExp(r'\s+')).length;
}

/// `3` -> `2026-10-17`, the key used to group rows into days.
String dayKey(DateTime value) {
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '${value.year}-$m-$d';
}
