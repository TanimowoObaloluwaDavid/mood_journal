import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/journal_entry.dart';
import '../error_log.dart';
import '../providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).valueOrNull ?? const AppSettings();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const _SectionHeader('Daily reminder'),
          SwitchListTile(
            title: const Text('Remind me to journal'),
            subtitle: Text(
              settings.remindersEnabled
                  ? 'Every day at ${_formatTime(settings)}'
                  : 'No reminders',
            ),
            secondary: const Icon(Icons.notifications_none_rounded),
            value: settings.remindersEnabled,
            onChanged: (value) => ref
                .read(appSettingsProvider.notifier)
                .patch((current) => current.copyWith(remindersEnabled: value)),
          ),
          if (settings.remindersEnabled)
            ListTile(
              enabled: settings.remindersEnabled,
              leading: const Icon(Icons.schedule_rounded),
              title: const Text('Reminder time'),
              trailing: Text(
                _formatTime(settings),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: () => _pickTime(context, ref, settings),
            ),
          SwitchListTile(
            title: const Text('Show a daily prompt'),
            secondary: const Icon(Icons.wb_sunny_outlined),
            value: settings.dailyPromptEnabled,
            onChanged: (value) => ref
                .read(appSettingsProvider.notifier)
                .patch((current) => current.copyWith(dailyPromptEnabled: value)),
          ),

          const _SectionHeader('Privacy'),
          SwitchListTile(
            title: const Text('Encrypt entries on this device'),
            subtitle: const Text(
              'AES-256-GCM. There is no cloud copy, so this cannot be recovered '
              'if the key is lost.',
            ),
            secondary: const Icon(Icons.lock_outline_rounded),
            value: settings.encryptionEnabled,
            onChanged: (value) => _toggleEncryption(context, ref, value),
          ),
          SwitchListTile(
            title: const Text('Require a passcode to open'),
            secondary: const Icon(Icons.pin_outlined),
            value: settings.passcodeEnabled,
            onChanged: (value) => ref
                .read(appSettingsProvider.notifier)
                .patch((current) => current.copyWith(passcodeEnabled: value)),
          ),

          const _SectionHeader('Appearance'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SegmentedButton<AppThemeMode>(
              segments: const [
                ButtonSegment(
                  value: AppThemeMode.system,
                  label: Text('Auto'),
                  icon: Icon(Icons.brightness_auto_rounded, size: 16),
                ),
                ButtonSegment(
                  value: AppThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_rounded, size: 16),
                ),
                ButtonSegment(
                  value: AppThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_rounded, size: 16),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (selection) => ref
                  .read(appSettingsProvider.notifier)
                  .patch((current) => current.copyWith(themeMode: selection.first)),
            ),
          ),

          const _SectionHeader('Your data'),
          const _ExportTile(),
          const _DiagnosticsTile(),

          const _SectionHeader('Danger zone'),
          ListTile(
            leading: Icon(Icons.delete_forever_rounded,
                color: Theme.of(context).colorScheme.error),
            title: Text(
              'Erase all entries',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            subtitle: const Text('Permanent. Cannot be undone.'),
            onTap: () => _confirmErase(context, ref),
          ),
        ],
      ),
    );
  }

  static String _formatTime(AppSettings settings) {
    final hour = settings.reminderHour.toString().padLeft(2, '0');
    final minute = settings.reminderMinute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: settings.reminderHour,
        minute: settings.reminderMinute,
      ),
    );
    if (picked == null) return;

    await ref.read(appSettingsProvider.notifier).patch(
          (current) => current.copyWith(
            reminderHour: picked.hour,
            reminderMinute: picked.minute,
          ),
        );
  }

  Future<void> _toggleEncryption(
    BuildContext context,
    WidgetRef ref,
    bool value,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(value ? 'Turn on encryption?' : 'Turn off encryption?'),
        content: Text(
          value
              ? 'Every entry on this device will be rewritten with AES-256-GCM. '
                  'There is no cloud backup, so a lost key means lost entries.'
              : 'Entry text will be stored in plain text. Anyone who can read '
                  "this device's storage can read your journal.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(value ? 'Encrypt' : 'Decrypt'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref
        .read(appSettingsProvider.notifier)
        .patch((current) => current.copyWith(encryptionEnabled: value));
  }

  Future<void> _confirmErase(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erase everything?'),
        content: const Text(
          'This deletes every entry and tag from this device. There is no '
          'undo and no backup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Erase'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final database = ref.read(appDatabaseProvider);

    await database.transaction(() async {
      await database.delete(database.journalEntries).go();
      await database.delete(database.tags).go();
    });

    ref.invalidate(entriesProvider);
    invalidateDerived(ref.invalidate);
    messenger.showSnackBar(
      const SnackBar(content: Text('All entries erased.')),
    );
  }
}

class _ExportTile extends ConsumerWidget {
  const _ExportTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.ios_share_rounded),
      title: const Text('Export as JSON'),
      subtitle: const Text('A plain-text copy of every entry'),
      onTap: () async {
        final entries =
            await ref.read(journalRepositoryProvider).getEntries(limit: 100000);

        final payload = jsonEncode({
          'exportedAt': DateTime.now().toIso8601String(),
          'count': entries.length,
          'entries': [for (final entry in entries) _toJson(entry)],
        });

        // share_plus is a heavy dependency for one button; the clipboard keeps
        // the app fully offline. Paste it wherever you want a backup.
        await Clipboard.setData(ClipboardData(text: payload));

        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Copied ${entries.length} entries '
              '(${(payload.length / 1024).round()} KB) to the clipboard.',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      },
    );
  }

  static Map<String, dynamic> _toJson(JournalEntry entry) => {
        'id': entry.id,
        'title': entry.title,
        'body': entry.body,
        'prompt': entry.prompt,
        'entryDate': entry.entryDate.toIso8601String(),
        'mood': entry.mood?.value,
        'wordCount': entry.wordCount,
        'isFavorite': entry.isFavorite,
        'createdAt': entry.createdAt.toIso8601String(),
        'updatedAt': entry.updatedAt.toIso8601String(),
        'tags': [for (final tag in entry.tags) tag.name],
      };
}

class _DiagnosticsTile extends ConsumerWidget {
  const _DiagnosticsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(errorLogProvider);

    return ListTile(
      leading: const Icon(Icons.bug_report_outlined),
      title: const Text('Diagnostics'),
      subtitle: Text(
        log.isEmpty
            ? 'No errors recorded'
            : '${log.entries.length} error'
                '${log.entries.length == 1 ? '' : 's'} recorded',
      ),
      trailing: log.isEmpty ? null : const Icon(Icons.chevron_right_rounded),
      onTap: log.isEmpty
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => Scaffold(
                    appBar: AppBar(
                      title: const Text('Diagnostics'),
                      actions: [
                        IconButton(
                          onPressed: log.clear,
                          icon: const Icon(Icons.delete_outline_rounded),
                          tooltip: 'Clear',
                        ),
                      ],
                    ),
                    body: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final error in log.entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              error,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}
