import '../models/app_settings.dart';
import '../models/insights_bundle.dart';
import '../models/journal_entry.dart';
import '../models/stats.dart';

/// Contract the presentation layer depends on. The Drift implementation lives
/// in `lib/data` and knows about encryption; nothing above this interface does.
abstract interface class JournalRepository {
  /// Timeline, newest day first.
  Future<List<JournalEntry>> getEntries({int limit = 200, int offset = 0});

  /// The most recent entry on [date], or null.
  Future<JournalEntry?> getEntryForDay(DateTime date);

  Future<JournalEntry?> getEntryById(String id);

  /// Creates on first call, updates afterwards. Safe to call on every autosave.
  Future<JournalEntry> saveEntry(JournalEntry entry);

  Future<void> deleteEntry(String id);

  Future<JournalEntry?> toggleFavorite(String id);

  /// Days with at least one entry, for the streak calculation.
  Future<Set<DateTime>> getActiveDays();

  Future<StreakStats> getStreaks();

  /// 182 days ending today, oldest first.
  Future<List<DayMood>> getHeatmap({int days = 182});

  Future<InsightsBundle> getInsights();

  Future<List<JournalEntry>> search(String query);

  Future<List<String>> getAllTags();

  Future<int> countEntries();

  /// Re-encrypts or decrypts every row in place after the setting is toggled.
  Future<void> migrateEncryption({required bool encrypt});
}

abstract interface class SettingsRepository {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}
