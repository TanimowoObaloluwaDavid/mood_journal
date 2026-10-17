import '../../core/utils/day_utils.dart';

/// Average mood for one calendar day, used to colour the heatmap.
class DayMood {
  const DayMood({
    required this.date,
    required this.average,
    required this.entryCount,
  });

  final DateTime date;

  /// `null` means "no entries that day" — deliberately not `0`.
  /// A zero would pull every average down and paint a blank day red.
  final double? average;

  final int entryCount;

  bool get hasData => average != null;
}

/// Current and historical streak.
class StreakStats {
  const StreakStats({
    required this.current,
    required this.longest,
    required this.totalDays,
  });

  const StreakStats.empty()
      : current = 0,
        longest = 0,
        totalDays = 0;

  /// Recomputes both streaks from the set of days that have at least one entry.
  ///
  /// Rules, all covered by unit tests:
  /// 1. No entries -> both 0.
  /// 2. Multiple entries on one day count once.
  /// 3. A gap of one empty day preserves the streak; two or more resets it.
  /// 4. A future-dated entry never extends the current streak, but it can
  ///    still be the longest if that is genuinely what happened.
  /// 5. If today has no entry but yesterday does, the current streak is still
  ///    alive — the day is not over yet.
  factory StreakStats.fromDays(Set<DateTime> days, {DateTime? now}) {
    if (days.isEmpty) return const StreakStats.empty();

    final today = startOfDay(now ?? DateTime.now());
    final sorted = days.map(startOfDay).toSet().toList()..sort();

    var longest = 1;
    var run = 1;
    for (var i = 1; i < sorted.length; i++) {
      if (daysBetween(sorted[i - 1], sorted[i]) == 1) {
        run++;
        if (run > longest) longest = run;
      } else {
        run = 1;
      }
    }

    var current = 0;
    var cursor = today;
    // Today may legitimately be empty — start from yesterday if so.
    if (!days.contains(cursor)) {
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      if (!days.contains(yesterday)) {
        return StreakStats(current: 0, longest: longest, totalDays: sorted.length);
      }
      cursor = yesterday;
    }

    while (days.contains(cursor)) {
      current++;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }

    return StreakStats(
      current: current,
      longest: longest < current ? current : longest,
      totalDays: sorted.length,
    );
  }

  final int current;
  final int longest;
  final int totalDays;

  @override
  bool operator ==(Object other) =>
      other is StreakStats &&
      other.current == current &&
      other.longest == longest &&
      other.totalDays == totalDays;

  @override
  int get hashCode => Object.hash(current, longest, totalDays);
}
