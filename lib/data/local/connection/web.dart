import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// SQLite compiled to WebAssembly, running in a web worker.
///
/// Drift picks the storage backend itself: OPFS when the browser exposes it,
/// IndexedDB otherwise. Both are covered by the same code path here.
///
/// Requires two files to be present in `web/` at runtime:
///   - `sqlite3.wasm`
///   - `drift_worker.dart.js` (compiled from `web/drift_worker.dart`)
///
/// The OPFS backend needs the page to be cross-origin isolated, which requires
/// COOP/COEP headers. Without them drift falls back to IndexedDB, which works
/// on any origin including plain localhost — slower on large databases, but it
/// means the app runs when someone just double-clicks a static build.
QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'mood_journal',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.dart.js'),
    );
    return result.resolvedExecutor;
  });
}
