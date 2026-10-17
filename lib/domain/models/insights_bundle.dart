import 'mood.dart';

/// Everything the Insights screen needs, from one pass over the data.
///
/// Charts must never N+1: the repository produces this in a single aggregate
/// query and the widgets just read fields.
class InsightsBundle {
  const InsightsBundle({
    required this.dailyAverages,
    required this.moodCounts,
    required this.moodByWeekday,
    required this.totalWords,
    required this.totalEntries,
    required this.longestEntryId,
    required this.topTags,
    required this.entriesThisMonth,
  });

  const InsightsBundle.empty()
      : dailyAverages = const [],
        moodCounts = const {},
        moodByWeekday = null,
        totalWords = 0,
        totalEntries = 0,
        longestEntryId = null,
        topTags = const [],
        entriesThisMonth = 0;

  /// Oldest → newest. Nulls excluded; gaps in dates are real signal.
  final List<DailyAverage> dailyAverages;

  /// How many entries exist per mood bucket.
  final Map<Mood, int> moodCounts;

  /// `DateTime.weekday` (1 = Monday) → average mood, or null if never logged.
  final Map<int, double>? moodByWeekday;

  final int totalWords;
  final int totalEntries;
  final String? longestEntryId;

  /// Tag name → count, already sorted descending and capped by the repository.
  final List<MapEntry<String, int>> topTags;

  final int entriesThisMonth;

  bool get isEmpty => totalEntries == 0;

  double get averageWordsPerEntry =>
      totalEntries == 0 ? 0 : (totalWords / totalEntries).toDouble();

  int get dominantMood {
    if (moodCounts.isEmpty) return 0;
    var best = Mood.okay;
    var bestCount = 0;
    for (final entry in moodCounts.entries) {
      if (entry.value > bestCount) {
        bestCount = entry.value;
        best = entry.key;
      }
    }
    return best.value;
  }
}

class DailyAverage {
  const DailyAverage({required this.date, required this.average});

  final DateTime date;
  final double average;
}
