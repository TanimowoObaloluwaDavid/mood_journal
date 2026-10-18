import 'package:flutter_test/flutter_test.dart';
import 'package:mood_journal/core/utils/day_utils.dart';
import 'package:mood_journal/domain/models/mood.dart';
import 'package:mood_journal/domain/models/stats.dart';

void main() {
  // Fixed "now" so the streak tests never depend on the wall clock.
  final now = DateTime(2026, 10, 17, 14, 30);

  DateTime day(int offset) => DateTime(2026, 10, 17 + offset);

  group('StreakStats.fromDays', () {
    test('no entries gives a zero streak, not a null', () {
      final stats = StreakStats.fromDays({}, now: now);
      expect(stats.current, 0);
      expect(stats.longest, 0);
      expect(stats.totalDays, 0);
    });

    test('single day today is a streak of 1', () {
      final stats = StreakStats.fromDays({day(0)}, now: now);
      expect(stats.current, 1);
      expect(stats.longest, 1);
    });

    test('a one-day gap preserves the streak', () {
      // Today, then skipping yesterday.
      final stats = StreakStats.fromDays({day(0), day(-2), day(-3)}, now: now);
      expect(stats.current, 1, reason: 'today stands alone');
      expect(stats.longest, 2, reason: 'the -2/-3 run is the longest');
    });

    test('a two-day gap resets the current streak', () {
      final stats = StreakStats.fromDays({day(-3), day(-4)}, now: now);
      expect(stats.current, 0);
      expect(stats.longest, 2);
    });

    test('multiple entries on one day count once', () {
      // Same date, different times of day.
      final days = {
        day(0),
        DateTime(2026, 10, 17, 8, 5),
        DateTime(2026, 10, 17, 23, 59),
      };
      final stats = StreakStats.fromDays(days, now: now);
      expect(stats.current, 1);
      expect(stats.totalDays, 1);
    });

    test('today being empty does not break a streak that ended yesterday', () {
      final stats = StreakStats.fromDays({day(-1), day(-2), day(-3)}, now: now);
      expect(stats.current, 3, reason: 'the day is not over yet');
      expect(stats.longest, 3);
    });

    test('a future entry never extends the current streak', () {
      final stats = StreakStats.fromDays({day(0), day(5)}, now: now);
      expect(stats.current, 1, reason: 'future days are not today');
      expect(stats.longest, 1);
    });

    test('longest is never shorter than current', () {
      final stats = StreakStats.fromDays({day(0), day(-1), day(-2)}, now: now);
      expect(stats.longest, greaterThanOrEqualTo(stats.current));
    });

    test('counts every distinct day logged', () {
      final stats = StreakStats.fromDays(
        {day(0), day(-2), day(-5), day(-6), day(-7)},
        now: now,
      );
      expect(stats.totalDays, 5);
    });
  });

  group('day bucketing', () {
    test('startOfDay drops the time component', () {
      expect(startOfDay(DateTime(2026, 10, 17, 23, 59, 59, 999)),
          DateTime(2026, 10, 17));
    });

    test('daysBetween counts whole days regardless of time of day', () {
      expect(daysBetween(DateTime(2026, 10, 17, 23, 59), DateTime(2026, 10, 18, 0, 1)), 1);
      expect(daysBetween(DateTime(2026, 10, 17), DateTime(2026, 10, 17, 23, 59)), 0);
    });

    test('a DST transition still yields exactly one day', () {
      // Most of Europe springs forward on the last Sunday of March.
      final before = DateTime(2026, 3, 28, 12);
      final after = DateTime(2026, 3, 30, 12);
      expect(daysBetween(before, after), 2);
      expect(daysBetween(before, DateTime(2026, 3, 29, 12)), 1);
    });

    test('daysInRange is inclusive on both ends', () {
      expect(
        daysInRange(DateTime(2026, 10, 15), DateTime(2026, 10, 17)).length,
        3,
      );
    });

    test('dayKey is zero-padded and sortable as a string', () {
      expect(dayKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(dayKey(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  group('countWords', () {
    test('empty and whitespace-only input is zero words', () {
      expect(countWords(''), 0);
      expect(countWords('   \n\t '), 0);
    });

    test('collapses arbitrary whitespace', () {
      expect(countWords('one   two\n\nthree'), 3);
    });

    test('a single word is one word', () {
      expect(countWords('hello'), 1);
    });
  });

  group('Mood', () {    test('fromValue returns null for out-of-range data', () {
      expect(Mood.fromValue(0), isNull);
      expect(Mood.fromValue(6), isNull);
      expect(Mood.fromValue(null), isNull);
    });

    test('fromAverage rounds and clamps', () {
      expect(Mood.fromAverage(3.6), Mood.good);
      expect(Mood.fromAverage(3.4), Mood.okay);
      expect(Mood.fromAverage(0.1), Mood.awful);
      expect(Mood.fromAverage(99), Mood.great);
    });

    test('every mood is in the 1..5 range so averages are meaningful', () {
      for (final mood in Mood.values) {
        expect(mood.value, inInclusiveRange(1, 5));
      }
    });
  });
}
