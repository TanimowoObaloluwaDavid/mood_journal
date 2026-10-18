import 'package:drift/drift.dart';

import 'connection/connection.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [JournalEntries, MoodTags, Tags, EntryTags, AppSettingsTable])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openConnection());

  /// Used by tests, backed by an in-memory database.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // Every timeline read is `ORDER BY entry_date DESC` and the heatmap
          // groups by the same column. Without these the 2 000-entry
          // performance target is missed.
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_entries_date '
            'ON journal_entries (entry_date DESC)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_entries_updated '
            'ON journal_entries (updated_at DESC)',
          );
        },
        beforeOpen: (details) async {
          // Required for the tag cascade to actually fire.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
