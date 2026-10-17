import 'package:drift/drift.dart';

@DataClassName('JournalEntryRow')
class JournalEntries extends Table {
  TextColumn get id => text()();

  /// Encrypted at rest when `encryptionEnabled`. See `CryptoService`.
  TextColumn get title => text().nullable()();

  /// Encrypted at rest when `encryptionEnabled`.
  TextColumn get body => text().withDefault(const Constant(''))();

  /// The prompt shown when the entry was created. Left plaintext: it is
  /// app-authored, not user content.
  TextColumn get prompt => text().nullable()();

  /// Midnight local. Several entries may share a day.
  DateTimeColumn get entryDate => dateTime()();

  /// 1–5, nullable. Plaintext so the heatmap and charts never decrypt a row.
  IntColumn get mood => integer().nullable()();

  /// 1–5, nullable. Reserved for v1.1; no UI writes it yet.
  IntColumn get energy => integer().nullable()();

  /// Denormalised so "total words" is a SUM, not a per-row decrypt.
  IntColumn get wordCount => integer().withDefault(const Constant(0))();

  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Secondary feelings per entry, so "great but anxious" is expressible.
@DataClassName('MoodTagRow')
class MoodTags extends Table {
  TextColumn get id => text()();
  TextColumn get entryId =>
      text().references(JournalEntries, #id, onDelete: KeyAction.cascade)();
  TextColumn get moodId => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TagRow')
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 64)();

  /// Required: `entry_tags.tag_id` references this column, and SQLite rejects
  /// a foreign key whose parent column is not a primary key or unique index.
  @override
  Set<Column<Object>> get primaryKey => {id};

  /// Tag names are case-sensitive here; the repository lower-cases before
  /// inserting so "Work" and "work" do not become two different tags.
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {name},
      ];
}

@DataClassName('EntryTagRow')
class EntryTags extends Table {
  TextColumn get entryId =>
      text().references(JournalEntries, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId => text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {entryId, tagId};
}

/// Key/value store so settings stay queryable and reactive without migrations.
@DataClassName('SettingRow')
class AppSettingsTable extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
