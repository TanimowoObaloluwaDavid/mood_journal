import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/day_utils.dart';
import '../../core/utils/result.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/insights_bundle.dart';
import '../../domain/models/journal_entry.dart';
import '../../domain/models/mood.dart';
import '../../domain/models/stats.dart';
import '../../domain/repositories/journal_repository.dart';
import '../local/app_database.dart';
import '../local/crypto_service.dart';

const _uuid = Uuid();

class DriftJournalRepository implements JournalRepository {
  DriftJournalRepository({
    required AppDatabase database,
    required CryptoService crypto,
    required bool encryptionEnabled,
  })  : _db = database,
        _crypto = crypto,
        _encryptionEnabled = encryptionEnabled;

  final AppDatabase _db;
  final CryptoService _crypto;
  bool _encryptionEnabled;

  set encryptionEnabled(bool value) => _encryptionEnabled = value;

  // ---------------------------------------------------------------- reads

  @override
  Future<List<JournalEntry>> getEntries({int limit = 200, int offset = 0}) async {
    final rows = await (_db.select(_db.journalEntries)
          ..orderBy([
            (t) => OrderingTerm.desc(t.entryDate),
            (t) => OrderingTerm.desc(t.createdAt),
          ])
          ..limit(limit, offset: offset))
        .get();

    return _hydrate(rows);
  }

  @override
  Future<JournalEntry?> getEntryForDay(DateTime date) async {
    final day = startOfDay(date);
    final row = await _db
        .customSelect(
          // `rowid DESC` is the tiebreaker that makes this deterministic:
          // two entries saved inside the same millisecond otherwise come back
          // in arbitrary order, and the home screen would show the wrong mood.
          'SELECT * FROM journal_entries WHERE entry_date = ? '
          'ORDER BY updated_at DESC, created_at DESC, rowid DESC LIMIT 1',
          variables: [Variable.withInt(_seconds(day))],
          readsFrom: {_db.journalEntries},
        )
        .getSingleOrNull();

    if (row == null) return null;
    final entry = _rowFrom(row);
    return _hydrateOne(entry, tags: await _tagsFor(entry.id));
  }

  /// drift stores DateTime as unix seconds, which is what SQLite's date
  /// functions expect and what a raw comparison needs.
  static int _seconds(DateTime value) => value.millisecondsSinceEpoch ~/ 1000;

  static DateTime _dateFrom(int seconds) =>
      DateTime.fromMillisecondsSinceEpoch(seconds * 1000);

  /// Rebuilds a row from a raw [QueryRow].
  ///
  /// drift 2.x has no `readTable` on `QueryRow` (that is a drift3 API), and
  /// `entry_date` / `created_at` / `updated_at` come back as raw seconds.
  JournalEntryRow _rowFrom(QueryRow row) => JournalEntryRow(
        id: row.read<String>('id'),
        title: row.read<String?>('title'),
        body: row.read<String>('body'),
        prompt: row.read<String?>('prompt'),
        entryDate: _dateFrom(row.read<int>('entry_date')),
        mood: row.read<int?>('mood'),
        energy: row.read<int?>('energy'),
        wordCount: row.read<int>('word_count'),
        isFavorite: row.read<bool>('is_favorite'),
        createdAt: _dateFrom(row.read<int>('created_at')),
        updatedAt: _dateFrom(row.read<int>('updated_at')),
      );

  @override
  Future<JournalEntry?> getEntryById(String id) async {
    final row = await (_db.select(_db.journalEntries)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    return _hydrateOne(row, tags: await _tagsFor(id));
  }

  Future<List<Tag>> _tagsFor(String entryId) async =>
      (await _tagsByEntryIds([entryId]))[entryId] ?? const [];

  @override
  Future<Set<DateTime>> getActiveDays() async {
    final query = _db.selectOnly(_db.journalEntries)
      ..addColumns([_db.journalEntries.entryDate])
      ..groupBy([_db.journalEntries.entryDate]);

    final rows = await query.get();
    return {for (final row in rows) startOfDay(row.read(_db.journalEntries.entryDate)!)};
  }

  @override
  Future<StreakStats> getStreaks() async {
    final days = await getActiveDays();
    return StreakStats.fromDays(days);
  }

  @override
  Future<List<DayMood>> getHeatmap({int days = 182}) async {
    final today = startOfToday();
    final from = DateTime(today.year, today.month, today.day - (days - 1));

    final query = _db.selectOnly(_db.journalEntries)
      ..addColumns([
        _db.journalEntries.entryDate,
        _db.journalEntries.mood.avg(),
        _db.journalEntries.id.count(),
      ])
      ..where(_db.journalEntries.entryDate.isBiggerOrEqualValue(from))
      ..groupBy([_db.journalEntries.entryDate]);

    final rows = await query.get();

    final buckets = <DateTime, DayMood>{};
    for (final row in rows) {
      final date = startOfDay(row.read(_db.journalEntries.entryDate)!);
      final average = row.read(_db.journalEntries.mood.avg());
      buckets[date] = DayMood(
        date: date,
        average: average,
        entryCount: row.read(_db.journalEntries.id.count()) ?? 0,
      );
    }

    // Fill the gaps so the heatmap always renders a full rectangle.
    return daysInRange(from, today)
        .map((day) => buckets[day] ?? DayMood(date: day, average: null, entryCount: 0))
        .toList(growable: false);
  }

  @override
  Future<InsightsBundle> getInsights() async {
    final days = await getActiveDays();
    if (days.isEmpty) return const InsightsBundle.empty();

    final moodAvg = _db.journalEntries.mood.avg();
    final moodCount = _db.journalEntries.id.count();

    // One grouped query covers the line chart, the heatmap and the streaks.
    final daily = await (_db.selectOnly(_db.journalEntries)
          ..addColumns([_db.journalEntries.entryDate, moodAvg, moodCount])
          ..groupBy([_db.journalEntries.entryDate])
          ..orderBy([OrderingTerm.asc(_db.journalEntries.entryDate)]))
        .get();

    final dailyAverages = <DailyAverage>[];
    final moodCounts = <Mood, int>{};

    for (final row in daily) {
      final date = row.read(_db.journalEntries.entryDate)!;
      final average = row.read(moodAvg);

      if (average != null) {
        dailyAverages.add(DailyAverage(date: startOfDay(date), average: average));
      }
    }

    // Distribution is derived from daily averages rather than a second query:
    // one entry per day is the common case, and buckets stay consistent with
    // what the calendar heatmap shows.
    for (final day in dailyAverages) {
      final mood = Mood.fromAverage(day.average);
      moodCounts[mood] = (moodCounts[mood] ?? 0) + 1;
    }

    final totals = await (_db.selectOnly(_db.journalEntries)
          ..addColumns([
            _db.journalEntries.id.count(),
            _db.journalEntries.wordCount.sum(),
          ]))
        .getSingle();

    final totalEntries = totals.read(_db.journalEntries.id.count()) ?? 0;
    final totalWords = totals.read(_db.journalEntries.wordCount.sum()) ?? 0;

    final longest = await (_db.select(_db.journalEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.wordCount)])
          ..limit(1))
        .getSingleOrNull();

    final monthStart = startOfMonth(DateTime.now());
    final thisMonth = await (_db.selectOnly(_db.journalEntries)
          ..addColumns([_db.journalEntries.id.count()])
          ..where(_db.journalEntries.entryDate.isBiggerOrEqualValue(monthStart)))
        .getSingle();

    return InsightsBundle(
      dailyAverages: dailyAverages,
      moodCounts: moodCounts,
      moodByWeekday: await _moodByWeekday(),
      totalWords: totalWords,
      totalEntries: totalEntries,
      longestEntryId: longest?.wordCount == 0 ? null : longest?.id,
      topTags: await _topTags(limit: 8),
      entriesThisMonth: thisMonth.read(_db.journalEntries.id.count()) ?? 0,
    );
  }

  /// SQLite has no WEEKDAY(), so extract it from the epoch.
  ///
  /// drift stores DateTime as unix seconds, hence 'unixepoch', and the extra
  /// 'localtime' matters: a streak recorded at 23:00 must land on the local day.
  Future<Map<int, double>?> _moodByWeekday() async {
    final rows = await _db
        .customSelect(
          r'''
          SELECT strftime('%w', entry_date, 'unixepoch', 'localtime') AS dow,
                 AVG(mood) AS avg_mood
          FROM journal_entries
          WHERE mood IS NOT NULL
          GROUP BY dow
          ''',
          readsFrom: {_db.journalEntries},
        )
        .get();

    if (rows.isEmpty) return null;

    // '%w' is 0=Sunday..6=Saturday; the app uses 1=Monday..7=Sunday.
    final map = <int, double>{};
    for (final row in rows) {
      final dow = row.read<int?>('dow');
      final average = row.read<double?>('avg_mood');
      if (dow != null && average != null) map[dow == 0 ? 7 : dow] = average;
    }
    return map;
  }

  Future<List<MapEntry<String, int>>> _topTags({required int limit}) async {
    final rows = await _db
        .customSelect(
          'SELECT t.name AS name, COUNT(*) AS uses FROM tags t '
          'JOIN entry_tags et ON et.tag_id = t.id '
          'GROUP BY t.id ORDER BY uses DESC, t.name ASC LIMIT ?',
          variables: [Variable.withInt(limit)],
          readsFrom: {_db.tags, _db.entryTags},
        )
        .get();

    return [
      for (final row in rows)
        MapEntry(row.read<String>('name'), row.read<int>('uses')),
    ];
  }

  @override
  Future<List<JournalEntry>> search(String query) async {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return const [];

    // `body` is ciphertext when encryption is on, so a SQL LIKE would never
    // match. Decrypt-and-filter is the honest option: a journal is thousands of
    // rows, not millions, and it never leaves the device.
    final rows = await (_db.select(_db.journalEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.entryDate)])
          ..limit(_searchScanLimit))
        .get();

    final tagsByEntry = await _tagsByEntryIds(rows.map((r) => r.id));

    final matches = <JournalEntry>[];
    for (final row in rows) {
      final entry = await _hydrateOne(row, tags: tagsByEntry[row.id]);
      if (_matches(entry, trimmed)) {
        matches.add(entry);
        if (matches.length >= _searchResultLimit) break;
      }
    }
    return matches;
  }

  static const _searchScanLimit = 2000;
  static const _searchResultLimit = 50;

  bool _matches(JournalEntry entry, String needle) {
    if (entry.body.toLowerCase().contains(needle)) return true;
    final title = entry.title?.toLowerCase();
    if (title != null && title.contains(needle)) return true;
    return entry.tags.any((tag) => tag.name.toLowerCase().contains(needle));
  }

  @override
  Future<List<String>> getAllTags() async {
    final rows = await (_db.select(_db.tags)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
    return rows.map((r) => r.name).toList(growable: false);
  }

  @override
  Future<int> countEntries() async {
    final row = await (_db.selectOnly(_db.journalEntries)
          ..addColumns([_db.journalEntries.id.count()]))
        .getSingle();
    return row.read(_db.journalEntries.id.count()) ?? 0;
  }

  // --------------------------------------------------------------- writes

  @override
  Future<JournalEntry> saveEntry(JournalEntry entry) async {
    final now = DateTime.now();
    final body = entry.body;
    final words = countWords(body);

    final storedTitle = (entry.title == null || entry.title!.trim().isEmpty)
        ? null
        : await _protect(entry.title!);
    final storedBody = await _protect(body);

    await _db.transaction(() async {
      await _db.into(_db.journalEntries).insertOnConflictUpdate(
            JournalEntriesCompanion(
              id: Value(entry.id),
              title: Value(storedTitle),
              body: Value(storedBody),
              prompt: Value(entry.prompt),
              entryDate: Value(startOfDay(entry.entryDate)),
              mood: Value(entry.mood?.value),
              energy: Value(entry.energy),
              wordCount: Value(words),
              isFavorite: Value(entry.isFavorite),
              createdAt: Value(entry.createdAt),
              updatedAt: Value(now),
            ),
          );

      await _syncTags(entry);
    });

    return entry.copyWith(
      title: entry.title,
      body: body,
      wordCount: words,
      updatedAt: now,
    );
  }

  Future<void> _syncTags(JournalEntry entry) async {
    await (_db.delete(_db.entryTags)..where((t) => t.entryId.equals(entry.id))).go();

    // Case-insensitive dedupe, keeping the first spelling the user typed.
    // SQLite's UNIQUE index is case-sensitive, so without this "Work" and
    // "work" would become two tags and every chip list would show both.
    final names = <String, String>{};
    for (final tag in entry.tags) {
      final trimmed = tag.name.trim();
      if (trimmed.isEmpty) continue;
      names.putIfAbsent(trimmed.toLowerCase(), () => trimmed);
    }
    if (names.isEmpty) return;

    for (final name in names.values) {
      final existing =
          await (_db.select(_db.tags)..where((t) => t.name.equals(name))).getSingleOrNull();

      final tagId = existing?.id ?? _uuid.v4();
      if (existing == null) {
        await _db
            .into(_db.tags)
            .insert(TagsCompanion(id: Value(tagId), name: Value(name)));
      }

      await _db.into(_db.entryTags).insert(
            EntryTagsCompanion(entryId: Value(entry.id), tagId: Value(tagId)),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  @override
  Future<void> deleteEntry(String id) async {
    await (_db.delete(_db.journalEntries)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<JournalEntry?> toggleFavorite(String id) async {
    return _db.transaction(() async {
      final row = await (_db.select(_db.journalEntries)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) return null;

      final next = !row.isFavorite;
      await (_db.update(_db.journalEntries)..where((t) => t.id.equals(id)))
          .write(JournalEntriesCompanion(
        isFavorite: Value(next),
        updatedAt: Value(DateTime.now()),
      ));

      // Re-read rather than reusing `row`: returning the pre-update snapshot
      // made every favourite tap look like it silently failed.
      final updated = await (_db.select(_db.journalEntries)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (updated == null) return null;

      return _hydrateOne(updated, tags: await _tagsFor(id));
    });
  }

  @override
  Future<void> migrateEncryption({required bool encrypt}) async {
    if (_encryptionEnabled == encrypt) return;

    final rows = await _db.select(_db.journalEntries).get();
    await _db.transaction(() async {
      for (final row in rows) {
        final plainTitle = row.title == null ? null : await _open(row.title!);
        final plainBody = await _open(row.body);
        await (_db.update(_db.journalEntries)..where((t) => t.id.equals(row.id)))
            .write(JournalEntriesCompanion(
          title: Value(await _reseal(plainTitle, encrypt: encrypt)),
          body: Value(await _reseal(plainBody, encrypt: encrypt)),
        ));
      }
    });

    _encryptionEnabled = encrypt;
  }

  // ------------------------------------------------------------ hydration

  /// Encrypts when the setting is on and the value is not already an envelope.
  ///
  /// The envelope check matters: a value that survived a previous toggle must
  /// not be encrypted a second time.
  Future<String> _protect(String plaintext) async {
    if (!_encryptionEnabled) return plaintext;
    if (CryptoService.isEnvelope(plaintext)) return plaintext;
    return _crypto.encrypt(plaintext);
  }

  Future<String> _open(String value) async {
    if (CryptoService.isEnvelope(value)) return _crypto.decrypt(value);
    return value;
  }

  /// The inverse of [_protect], used when the user flips the setting.
  Future<String> _reseal(String? plaintext, {required bool encrypt}) async {
    if (plaintext == null) return '';
    if (!encrypt) return plaintext;
    if (CryptoService.isEnvelope(plaintext)) return plaintext;
    return _crypto.encrypt(plaintext);
  }

  Future<List<JournalEntry>> _hydrate(List<JournalEntryRow> rows) async {
    if (rows.isEmpty) return const [];
    final tags = await _tagsByEntryIds(rows.map((r) => r.id));
    final entries = <JournalEntry>[];
    for (final row in rows) {
      entries.add(await _hydrateOne(row, tags: tags[row.id]));
    }
    return entries;
  }

  Future<JournalEntry> _hydrateOne(
    JournalEntryRow row, {
    List<Tag>? tags,
}) async {
    return JournalEntry(
      id: row.id,
      title: await _open(row.title ?? '').then((v) => v.isEmpty ? null : v),
      body: await _open(row.body),
      prompt: row.prompt,
      entryDate: row.entryDate,
      mood: Mood.fromValue(row.mood),
      energy: row.energy,
      wordCount: row.wordCount,
      isFavorite: row.isFavorite,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      tags: tags ?? const [],
    );
  }

  Future<Map<String, List<Tag>>> _tagsByEntryIds(Iterable<String> ids) async {
    final idList = ids.toList(growable: false);
    if (idList.isEmpty) return const {};

    final query = _db.select(_db.entryTags).join([
      innerJoin(_db.tags, _db.tags.id.equalsExp(_db.entryTags.tagId)),
    ])
      ..where(_db.entryTags.entryId.isIn(idList))
      ..orderBy([OrderingTerm.asc(_db.tags.name)]);

    final rows = await query.get();
    final result = <String, List<Tag>>{};
    for (final row in rows) {
      final entryTag = row.readTable(_db.entryTags);
      final tag = row.readTable(_db.tags);
      result.putIfAbsent(entryTag.entryId, () => []).add(Tag(id: tag.id, name: tag.name));
    }
    return result;
  }
}

class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db);

  final AppDatabase _db;
  static const _key = 'app_settings';

  @override
  Future<AppSettings> load() async {
    final row = await (_db.select(_db.appSettingsTable)
          ..where((t) => t.key.equals(_key)))
        .getSingleOrNull();

    if (row == null) return const AppSettings();
    try {
      final decoded = jsonDecode(row.value) as Map<String, dynamic>;
      return AppSettings.fromJson(decoded);
    } on FormatException {
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    await _db.into(_db.appSettingsTable).insertOnConflictUpdate(
          AppSettingsTableCompanion(
            key: Value(_key),
            value: Value(jsonEncode(settings.toJson())),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }
}

/// Convenience for callers that want the error path handled for them.
Future<Result<T>> guard<T>(Future<T> Function() action) async {
  try {
    return Ok<T>(await action());
  } catch (error) {
    return Err<T>(AppException.from(error));
  }
}
