import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/day_utils.dart';
import '../data/local/app_database.dart';
import '../data/local/crypto_service.dart';
import '../data/repositories/drift_journal_repository.dart';
import '../domain/models/app_settings.dart';
import '../domain/models/insights_bundle.dart';
import '../domain/models/journal_entry.dart';
import '../domain/models/mood.dart';
import '../domain/models/stats.dart';
import '../domain/repositories/journal_repository.dart';

const _uuid = Uuid();

/// ---------------------------------------------------------------- infrastructure

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final cryptoServiceProvider = Provider<CryptoService>((ref) => CryptoService());

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return DriftSettingsRepository(ref.watch(appDatabaseProvider));
});

/// One repository instance for the app's lifetime.
///
/// The encryption flag is pushed in from settings rather than baked in at
/// construction, so toggling it does not orphan every cached future.
final journalRepositoryProvider = Provider<JournalRepository>((ref) {
  final repo = DriftJournalRepository(
    database: ref.watch(appDatabaseProvider),
    crypto: ref.watch(cryptoServiceProvider),
    encryptionEnabled: true,
  );

  ref.listen(appSettingsProvider, (previous, next) {
    final enabled = next.valueOrNull?.encryptionEnabled;
    if (enabled != null) repo.encryptionEnabled = enabled;
  });

  return repo;
});

/// Client-side id generation, so an entry can be created before it is saved.
final uuidProvider = Provider<String Function()>((ref) => _uuid.v4);

// ---------------------------------------------------------------- settings

class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.watch(settingsRepositoryProvider).load();

  /// Applies a change and persists it.
  ///
  /// Named `patch` rather than `update` because `AsyncNotifierBase.update` is a
  /// Riverpod method with a different signature — overriding it would be a bug.
  Future<void> patch(AppSettings Function(AppSettings current) transform) async {
    final current = state.valueOrNull ?? const AppSettings();
    final next = transform(current);

    final encryptionFlipped =
        current.encryptionEnabled != next.encryptionEnabled;

    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).save(next);

    if (encryptionFlipped) {
      // Rewrite every row before the flag flips, otherwise the app briefly
      // reads ciphertext as plaintext.
      await ref
          .read(journalRepositoryProvider)
          .migrateEncryption(encrypt: next.encryptionEnabled);
      ref.invalidate(entriesProvider);
    }
  }
}

final appSettingsProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(SettingsController.new);

// ---------------------------------------------------------------- timeline

class EntriesController extends AsyncNotifier<List<JournalEntry>> {
  @override
  Future<List<JournalEntry>> build() =>
      ref.watch(journalRepositoryProvider).getEntries(limit: 500);

  Future<JournalEntry?> save(JournalEntry entry) async {
    final saved = await ref.read(journalRepositoryProvider).saveEntry(entry);
    invalidateDerived(ref.invalidate);
    return saved;
  }

  Future<void> remove(String id) async {
    await ref.read(journalRepositoryProvider).deleteEntry(id);
    invalidateDerived(ref.invalidate);
  }

  Future<void> toggleFavorite(String id) async {
    await ref.read(journalRepositoryProvider).toggleFavorite(id);
    invalidateDerived(ref.invalidate);
  }
}

final entriesProvider =
    AsyncNotifierProvider<EntriesController, List<JournalEntry>>(
        EntriesController.new);

/// Everything derived from the timeline. Bumped together so one write never
/// leaves the streak and the chart disagreeing with the list.
final derivedProviders = <ProviderOrFamily>[
  todayEntryProvider,
  streakProvider,
  heatmapProvider,
  insightsProvider,
  entryCountsProvider,
];

/// Takes `ref.invalidate` as a callback rather than a `Ref`, because in
/// Riverpod 2.x a `WidgetRef` is not a `Ref` and a mutation can be triggered
/// from either side — a button handler or a notifier method.
void invalidateDerived(void Function(ProviderOrFamily provider) invalidate) {
  for (final provider in derivedProviders) {
    invalidate(provider);
  }
}

final entryCountsProvider = FutureProvider<int>((ref) async {
  // Watches the timeline so the badge updates on its own.
  ref.watch(entriesProvider);
  return ref.read(journalRepositoryProvider).countEntries();
});

final entryProvider = FutureProvider.autoDispose
    .family<JournalEntry?, String>((ref, id) async {
  ref.watch(entriesProvider);
  return ref.read(journalRepositoryProvider).getEntryById(id);
});

final todayEntryProvider = FutureProvider<JournalEntry?>((ref) async {
  ref.watch(entriesProvider);
  return ref.read(journalRepositoryProvider).getEntryForDay(DateTime.now());
});

// ---------------------------------------------------------------- stats

final streakProvider = FutureProvider<StreakStats>((ref) async {
  ref.watch(entriesProvider);
  return ref.read(journalRepositoryProvider).getStreaks();
});

final heatmapProvider = FutureProvider<List<DayMood>>((ref) async {
  ref.watch(entriesProvider);
  return ref.read(journalRepositoryProvider).getHeatmap();
});

final insightsProvider = FutureProvider<InsightsBundle>((ref) async {
  ref.watch(entriesProvider);
  return ref.read(journalRepositoryProvider).getInsights();
});

// ---------------------------------------------------------------- search

class SearchQueryController extends Notifier<String> {
  @override
  String build() => '';
  void update(String value) => state = value;
  void clear() => state = '';
}

final searchQueryProvider =
    NotifierProvider<SearchQueryController, String>(SearchQueryController.new);

final searchResultsProvider = FutureProvider.autoDispose
    .family<List<JournalEntry>, String>((ref, query) async {
  if (query.trim().isEmpty) return const [];
  return ref.read(journalRepositoryProvider).search(query);
});

final allTagsProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(entriesProvider);
  return ref.read(journalRepositoryProvider).getAllTags();
});

// ---------------------------------------------------------------- prompts

final dailyPromptProvider = Provider<String>((ref) {
  final enabled =
      ref.watch(appSettingsProvider).valueOrNull?.dailyPromptEnabled ?? true;
  return enabled ? JournalPrompts.forDay(DateTime.now()) : '';
});

// ---------------------------------------------------------------- draft

/// Buffer for an entry being written, so a mood tap survives navigation.
class TodayDraft {
  const TodayDraft({this.entryId, this.mood, this.body = ''});

  final String? entryId;
  final Mood? mood;
  final String body;

  bool get isDirty => mood != null || body.trim().isNotEmpty;

  TodayDraft copyWith({
    String? Function()? entryId,
    Mood? Function()? mood,
    String? body,
  }) {
    return TodayDraft(
      entryId: entryId != null ? entryId() : this.entryId,
      mood: mood != null ? mood() : this.mood,
      body: body ?? this.body,
    );
  }
}

class TodayDraftController extends Notifier<TodayDraft> {
  @override
  TodayDraft build() => const TodayDraft();

  void seed(JournalEntry entry) {
    state = TodayDraft(
      entryId: entry.id,
      mood: entry.mood,
      body: entry.body,
    );
  }

  void setMood(Mood mood) => state = state.copyWith(mood: () => mood);
  void setBody(String body) => state = state.copyWith(body: body);
  void reset() => state = const TodayDraft();
}

final todayDraftProvider =
    NotifierProvider<TodayDraftController, TodayDraft>(TodayDraftController.new);

// ---------------------------------------------------------------- helpers

/// Day helper exposed for widgets that need "is this entry from today".
bool isFromToday(DateTime date) => daysBetween(startOfDay(date), startOfToday()) == 0;
