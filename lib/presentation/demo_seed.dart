import '../core/utils/day_utils.dart';
import '../domain/models/journal_entry.dart';
import '../domain/models/mood.dart';
import '../domain/repositories/journal_repository.dart';

/// Fills the journal with plausible sample data.
///
/// Screenshots and demo videos of an empty journal are worthless — they show
/// an empty box rather than the product. This seeds ~11 weeks of entries with a
/// slow upward mood trend, a realistic weekday effect, and some genuine gaps.
///
/// Strictly opt-in. Production builds never call it, and because the flag is a
/// compile-time constant the whole file is tree-shaken away unless enabled:
///
/// ```bash
/// flutter run --dart-define=DEMO_DATA=true
/// ```
class DemoSeeder {
  const DemoSeeder._();

  static const bool enabled = bool.fromEnvironment('DEMO_DATA');

  static const _days = 78;

  /// Deterministic PRNG so a re-seed produces the identical journal, which
  /// keeps screenshots stable between runs.
  static int _seed = 20261018;

  static double _next() {
    // xorshift32
    _seed ^= _seed << 13;
    _seed ^= _seed >> 17;
    _seed ^= _seed << 5;
    return (_seed & 0x7fffffff) / 0x7fffffff;
  }

  static int _int(int minInclusive, int maxExclusive) =>
      minInclusive + (_next() * (maxExclusive - minInclusive)).floor();

  static Future<void> seed(JournalRepository repo) async {
    // Seeding ~78 encrypted entries takes a noticeable moment. Only do it on a
    // genuinely empty journal so repeat launches are instant.
    if (await repo.countEntries() > 0) return;

    final today = startOfToday();

    final bodies = <String>[
      'Long walk before work. Slept badly but the air helped.',
      'Shipped the thing I had been putting off for two weeks.',
      'Called Mum. She sounded good. We should visit soon.',
      'Argument with R. Still unclear who was right, probably both.',
      'Quiet day. Nothing much happened and that was fine.',
      'Review went well. Two things to fix, neither urgent.',
      'Could not focus. Too many tabs open, too much noise.',
      'Cooked properly for once instead of standing at the counter.',
      'Ran. Only twenty minutes but it was good to be outside.',
      'Deadline moved up. Not thrilled about it.',
      'Read for an hour before bed. Fell asleep immediately.',
      'Money worry again. Need to look at the numbers this week.',
      'Good coffee and a sunny window. Small things.',
      'Told someone how I was feeling. Harder than expected.',
      'Nothing worth writing down today.',
      'The fix was one line. Spent four hours finding it.',
      'Tired in a way sleep does not fix.',
      'Dinner with friends. Laughed a lot. Good evening.',
      'Sorted the flat. Feels better already.',
      'Anxious about tomorrow, trying not to think about it.',
      'Learned something at work I did not expect to enjoy.',
      'Rain all day. Stayed in and did not mind it.',
      'Forgot to eat until four. Sloppy.',
      'Saw the doctor. Nothing serious. Relieved.',
      'Finally finished the book. Wanted another one immediately.',
    ];

    final tags = <String>[
      'work', 'sleep', 'family', 'health', 'money', 'friends', 'reading', 'exercise',
    ];

    for (var offset = _days - 1; offset >= 0; offset--) {
      final date = DateTime(today.year, today.month, today.day - offset);

      // Roughly one day in six is missing — a real journal has gaps, and
      // showing a flawless grid would misrepresent the streak feature.
      if (offset > 0 && _next() < 0.16) continue;

      // Slow improvement across the whole period.
      final progress = (_days - offset) / _days;
      var score = 2.6 + progress * 1.1;

      // Weekends run lower; midweek runs higher.
      final weekend = date.weekday >= DateTime.saturday;
      score += weekend ? -0.45 : 0.25;

      // Noise, then clamp to the 1..5 range the charts expect.
      score += (_next() - 0.5) * 1.5;
      final mood = Mood.fromAverage(score);

      final isToday = offset == 0;
      // Recent days always get text so the timeline looks lived-in, and so the
      // editor screenshot opens on an entry with something in it.
      final hasText = !isToday && (_next() > 0.22 || offset <= 2);
      final body = hasText ? bodies[_int(0, bodies.length)] : '';
      final favorite = _next() < 0.08;

      final entry = JournalEntry.empty(
        id: 'demo-$offset',
        date: date,
        prompt: 'What went well today?',
        mood: mood,
      ).copyWith(
        body: body,
        isFavorite: favorite,
        tags: [
          for (final tag in tags)
            if (_next() < 0.16) Tag(id: tag, name: tag),
        ],
      );

      await repo.saveEntry(entry);
    }
  }
}
