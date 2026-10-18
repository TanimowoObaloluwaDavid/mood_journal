import 'package:drift/drift.dart';

/// Reached only on a platform with neither `dart:io` nor `dart:js_interop`,
/// which should be impossible. Failing loudly beats silently losing entries.
QueryExecutor openConnection() => throw UnsupportedError(
      'No database implementation for this platform. '
      'Supported targets: Android, iOS, Windows, macOS, Linux, and the web.',
    );
