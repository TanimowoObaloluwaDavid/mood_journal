import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import 'providers.dart';
import 'router.dart';

class MoodJournalApp extends ConsumerWidget {
  const MoodJournalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Bootstrapping settings here, rather than in main(), means the very first
    // frame already has the right theme — no flash of the wrong brightness.
    final settings = ref.watch(appSettingsProvider);

    final themeMode = switch (settings.valueOrNull?.themeMode ?? AppThemeMode.system) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };

    return MaterialApp.router(
      title: 'Mood Journal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
