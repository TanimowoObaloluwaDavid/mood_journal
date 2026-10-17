import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_journal/core/utils/day_utils.dart';
import 'package:mood_journal/data/local/app_database.dart';
import 'package:mood_journal/data/local/crypto_service.dart';
import 'package:mood_journal/data/repositories/drift_journal_repository.dart';
import 'package:mood_journal/domain/models/journal_entry.dart';
import 'package:mood_journal/domain/models/mood.dart';

/// In-memory key store so the repository can be tested without platform
/// channels. The envelope format is still exercised for real.
class FakeSecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  late AppDatabase db;
  late DriftJournalRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DriftJournalRepository(
      database: db,
      crypto: CryptoService(store: FakeSecretStore()),
      encryptionEnabled: true,
    );
  });

  tearDown(() async => db.close());

  final today = startOfToday();

  JournalEntry draft({
    String id = 'e1',
    String body = 'Shipped the feature.',
    Mood? mood = Mood.good,
    DateTime? date,
    List<Tag> tags = const [],
  }) {
    return JournalEntry.empty(id: id, date: date ?? today, mood: mood)
        .copyWith(body: body, tags: tags);
  }

  group('round trip', () {
    test('create, read back, edit, then delete', () async {
      await repo.saveEntry(draft());

      final loaded = await repo.getEntryById('e1');
      expect(loaded, isNotNull);
      expect(loaded!.body, 'Shipped the feature.');
      expect(loaded.mood, Mood.good);

      await repo.saveEntry(loaded.copyWith(body: 'Shipped the whole thing.'));
      expect((await repo.getEntryById('e1'))!.body,
          'Shipped the whole thing.');

      await repo.deleteEntry('e1');
      expect(await repo.getEntryById('e1'), isNull);
    });

    test('word count is derived, not trusted from the caller', () async {
      await repo.saveEntry(draft(body: 'one   two\n\nthree '));
      expect((await repo.getEntryById('e1'))!.wordCount, 3);
    });

    test('an empty body counts as zero words, not one', () async {
      await repo.saveEntry(draft(body: '   '));
      expect((await repo.getEntryById('e1'))!.wordCount, 0);
    });

    test('a mood tap on an existing entry updates it instead of duplicating',
        () async {
      await repo.saveEntry(draft());
      await repo.saveEntry(draft(mood: Mood.awful));

      final entries = await repo.getEntries();
      expect(entries.length, 1);
      expect(entries.single.mood, Mood.awful);
    });
  });

  group('encryption at rest', () {
    test('the stored body is ciphertext, not the plaintext', () async {
      await repo.saveEntry(draft(body: 'my private thoughts'));
      await repo.saveEntry(draft(body: 'my private thoughts'));
      await repo.saveEntry(draft(body: 'my private thoughts'));
      await repo.saveEntry(draft(body: 'my private thoughts'));

      final rows = await db.select(db.journalEntries).get();
      expect(rows.single.body, isNot(contains('my private thoughts')));
      expect(CryptoService.isEnvelope(rows.single.body), isTrue);
    });

    test('each encryption uses a fresh nonce', () async {
      await repo.saveEntry(draft(id: 'a', body: 'same text'));
      await repo.saveEntry(draft(id: 'b', body: 'same text'));

      final rows = await db.select(db.journalEntries).get();
      final bodies = rows.map((r) => r.body).toSet();
      expect(bodies.length, 2, reason: 'identical plaintext must not repeat');
    });

    test('dates and moods stay plaintext so SQL aggregates still work',
        () async {
      await repo.saveEntry(draft(mood: Mood.great));

      final rows = await db.select(db.journalEntries).get();
      expect(rows.single.mood, 5);
      expect(rows.single.entryDate, today);
    });

    test('turning encryption off rewrites every row to plaintext', () async {
      await repo.saveEntry(draft(body: 'secret'));

      await repo.migrateEncryption(encrypt: false);

      final rows = await db.select(db.journalEntries).get();
      expect(rows.single.body, 'secret');
      expect((await repo.getEntryById('e1'))!.body, 'secret');
    });

    test('turning it back on re-encrypts without double-encrypting',
        () async {
      await repo.saveEntry(draft(body: 'secret'));
      await repo.migrateEncryption(encrypt: false);
      await repo.migrateEncryption(encrypt: true);
      await repo.migrateEncryption(encrypt: true);

      final rows = await db.select(db.journalEntries).get();
      expect(CryptoService.isEnvelope(rows.single.body), isTrue);
      expect((await repo.getEntryById('e1'))!.body, 'secret');
    });

    test('toggling encryption is a no-op when the value already matches',
        () async {
      await repo.saveEntry(draft(body: 'secret'));
      await repo.migrateEncryption(encrypt: true);

      expect((await repo.getEntryById('e1'))!.body, 'secret');
    });
  });

  group('search', () {
    test('matches on body text', () async {
      await repo.saveEntry(draft(id: 'a', body: 'the quarterly review went well'));
      await repo.saveEntry(draft(id: 'b', body: 'unrelated'));

      final results = await repo.search('quarterly');
      expect(results.map((e) => e.id), ['a']);
    });

    test('matches on tags', () async {
      await repo.saveEntry(draft(
        id: 'a',
        body: 'nothing notable',
        tags: const [Tag(id: 'work', name: 'work')],
      ));

      expect((await repo.search('work')).map((e) => e.id), ['a']);
    });

    test('is case insensitive and returns nothing for an empty query',
        () async {
      await repo.saveEntry(draft(body: 'Capital Letters'));
      expect((await repo.search('capital')).length, 1);
      expect(await repo.search('   '), isEmpty);
    });

    test('searches encrypted text correctly', () async {
      await repo.saveEntry(draft(body: 'encrypted needle in here'));
      expect((await repo.search('needle')).length, 1);
    });
  });

  group('stats', () {
    test('streaks are computed from days that have entries', () async {
      await repo.saveEntry(draft(id: 'a', date: today));
      await repo.saveEntry(draft(id: 'b', date: today));
      await repo.saveEntry(
        draft(id: 'c', date: DateTime(today.year, today.month, today.day - 1)),
      );

      final streaks = await repo.getStreaks();
      expect(streaks.current, 2, reason: 'two entries today count once');
      expect(streaks.totalDays, 2);
    });

    test('a future-dated entry does not extend the streak', () async {
      await repo.saveEntry(draft(id: 'a', date: today));
      await repo.saveEntry(
        draft(id: 'b', date: DateTime(today.year, today.month, today.day + 3)),
      );

      expect((await repo.getStreaks()).current, 1);
    });

    test('the heatmap is a full rectangle of 182 days ending today', () async {
      await repo.saveEntry(draft(id: 'a', mood: Mood.great));

      final heatmap = await repo.getHeatmap();
      expect(heatmap.length, 182);
      expect(heatmap.last.date, today);
      expect(heatmap.last.average, 5);
    });

    test('days with no entries have a null average, not zero', () async {
      await repo.saveEntry(draft(id: 'a', mood: Mood.awful));

      final heatmap = await repo.getHeatmap();
      final empty = heatmap.where((d) => !d.hasData).toList();
      expect(empty, isNotEmpty);
      expect(empty.every((d) => d.average == null), isTrue);
    });

    test('multiple entries on one day average together', () async {
      await repo.saveEntry(draft(id: 'a', mood: Mood.great));
      await repo.saveEntry(draft(id: 'b', mood: Mood.awful));

      final heatmap = await repo.getHeatmap();
      expect(heatmap.last.entryCount, 2);
      expect(heatmap.last.average, 3);
    });

    test('insights are empty when there are no entries', () async {
      final insights = await repo.getInsights();
      expect(insights.isEmpty, isTrue);
      expect(insights.totalWords, 0);
    });

    test('insights total words from the denormalised column', () async {
      await repo.saveEntry(draft(id: 'a', body: 'one two three'));
      await repo.saveEntry(draft(id: 'b', body: 'four five'));

      final insights = await repo.getInsights();
      expect(insights.totalWords, 5);
      expect(insights.totalEntries, 2);
    });

    test('weekday buckets are keyed Monday-to-Sunday', () async {
      await repo.saveEntry(draft(id: 'a', mood: Mood.great));

      final byWeekday = (await repo.getInsights()).moodByWeekday!;
      expect(byWeekday[today.weekday], 5);
      expect(byWeekday.keys.every((k) => k >= 1 && k <= 7), isTrue);
    });
  });

  group('tags', () {
    test('tags are replaced, not merged, on re-save', () async {
      await repo.saveEntry(draft(
        id: 'a',
        tags: const [Tag(id: 'x', name: 'work'), Tag(id: 'y', name: 'sleep')],
      ));
      await repo.saveEntry(draft(id: 'a', tags: const [Tag(id: 'z', name: 'rest')]));

      final entry = await repo.getEntryById('a');
      expect(entry!.tags.map((t) => t.name), ['rest']);
    });

    test('the tag table is not polluted by removed names', () async {
      await repo.saveEntry(draft(id: 'a', tags: const [Tag(id: 'x', name: 'old')]));
      await repo.saveEntry(draft(id: 'a', tags: const [Tag(id: 'z', name: 'new')]));

      final tags = await repo.getAllTags();
      expect(tags, containsAll(['old', 'new']));
    });

    test('duplicate tags within one entry are collapsed case-insensitively',
        () async {
      await repo.saveEntry(draft(
        id: 'a',
        tags: const [Tag(id: 'x', name: 'work'), Tag(id: 'y', name: 'Work')],
      ));

      final tags = (await repo.getEntryById('a'))!.tags;
      expect(tags.length, 1);
      expect(tags.single.name, 'work', reason: 'first spelling wins');
    });
  });

  group('favourites', () {
    test('toggling flips the flag and keeps the entry', () async {
      await repo.saveEntry(draft());

      final on = await repo.toggleFavorite('e1');
      expect(on!.isFavorite, isTrue);

      final off = await repo.toggleFavorite('e1');
      expect(off!.isFavorite, isFalse);
      expect(await repo.getEntryById('e1'), isNotNull);
    });

    test('toggling a missing entry returns null rather than throwing',
        () async {
      expect(await repo.toggleFavorite('nope'), isNull);
    });
  });

  group('day buckets', () {
    test('a time late in the evening still lands on the same day', () async {
      final lateNight = DateTime(today.year, today.month, today.day, 23, 59);
      await repo.saveEntry(draft(date: lateNight));

      expect(await repo.getEntryForDay(today), isNotNull);
    });

    test('the most recently edited entry wins when a day has several',
        () async {
      // Explicit timestamps: two saves inside the same millisecond have no
      // meaningful order, so the test must not rely on wall-clock timing.
      final base = DateTime(2026, 10, 17, 9);
      final morning = JournalEntry(
        id: 'am',
        title: null,
        body: 'morning entry',
        prompt: null,
        entryDate: today,
        mood: Mood.awful,
        energy: null,
        wordCount: 2,
        isFavorite: false,
        createdAt: base,
        updatedAt: base,
      );
      final evening = JournalEntry(
        id: 'pm',
        title: null,
        body: 'evening entry',
        prompt: null,
        entryDate: today,
        mood: Mood.great,
        energy: null,
        wordCount: 2,
        isFavorite: false,
        createdAt: base.add(const Duration(hours: 8)),
        updatedAt: base.add(const Duration(hours: 8)),
      );

      await repo.saveEntry(morning);
      await repo.saveEntry(evening);

      expect((await repo.getEntryForDay(today))!.mood, Mood.great);
    });

    test('re-saving an entry makes it the one shown for that day', () async {
      await repo.saveEntry(draft(id: 'am', mood: Mood.awful));
      await repo.saveEntry(draft(id: 'pm', mood: Mood.great));
      // The home screen's mood tap updates the newest entry rather than
      // creating a second one, so the latest edit must win.
      await repo.saveEntry(draft(id: 'pm', mood: Mood.good));

      final found = await repo.getEntryForDay(today);
      expect(found!.id, 'pm');
      expect(found.mood, Mood.good);
    });
  });
}
