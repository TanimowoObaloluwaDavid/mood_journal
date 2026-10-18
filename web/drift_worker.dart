/// Compiled to `web/drift_worker.dart.js`, which the app loads at runtime.
///
/// Without this worker, drift has nowhere to run WASM SQLite and `WasmDatabase.open`
/// fails. Recompile after changing anything here:
///
/// ```bash
/// dart compile js -O4 web/drift_worker.dart -o web/drift_worker.dart.js
/// ```
library;

import 'package:drift/wasm.dart';

void main() => WasmDatabase.workerMainForOpen();
