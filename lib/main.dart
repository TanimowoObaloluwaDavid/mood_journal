import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'presentation/app.dart';
import 'presentation/demo_seed.dart';
import 'presentation/error_log.dart';
import 'presentation/providers.dart';

Future<void> main() async {
  // WidgetsFlutterBinding must exist before anything touches a platform
  // channel. runApp is deliberately not delayed: the cold-start budget in
  // SPEC.md §7 depends on this.
  WidgetsFlutterBinding.ensureInitialized();

  final errorLog = ErrorLog();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    errorLog.add(details.exceptionAsString());
  };

  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    errorLog.add('$error\n$stack');
    return true;
  };

  // Demo builds only. Tree-shaken out entirely unless DEMO_DATA=true, so a
  // release build never ships sample entries.
  if (DemoSeeder.enabled) {
    final container = ProviderContainer();
    await DemoSeeder.seed(container.read(journalRepositoryProvider));
    container.dispose();
  }

  runApp(
    ProviderScope(
      overrides: [errorLogProvider.overrideWithValue(errorLog)],
      child: const MoodJournalApp(),
    ),
  );
}
