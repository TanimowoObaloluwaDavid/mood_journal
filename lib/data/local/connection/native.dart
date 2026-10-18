import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// SQLite on a background isolate, in the app's private documents directory.
///
/// The isolate matters: `screencap`-level jank on the timeline would otherwise
/// come from SQLite work competing with the frame budget.
QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'mood_journal.sqlite'));

    return NativeDatabase.createInBackground(
      file,
      // WAL lets the debounced autosave write proceed without blocking the
      // timeline read that follows it.
      setup: (database) {
        database.execute('PRAGMA journal_mode = WAL;');
        database.execute('PRAGMA synchronous = NORMAL;');
      },
    );
  });
}
