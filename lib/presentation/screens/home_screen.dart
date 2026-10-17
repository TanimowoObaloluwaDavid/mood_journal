import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/mood_palette.dart';
import '../../domain/models/journal_entry.dart';
import '../../domain/models/mood.dart';
import '../providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/entry_card.dart';
import '../widgets/mood_picker.dart';
import '../widgets/streak_banner.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _saving = false;

  /// Tapping an emoji persists immediately. This is the whole product in one
  /// gesture: no Save button, no keyboard, no friction.
  Future<void> _pickMood(Mood mood) async {
    if (_saving) return;
    setState(() => _saving = true);

    final existing = ref.read(todayEntryProvider).valueOrNull;

    final draft = existing ??
        JournalEntry.empty(
          id: ref.read(uuidProvider)(),
          prompt: ref.read(dailyPromptProvider),
        );

    try {
      await ref.read(entriesProvider.notifier).save(
            draft.copyWith(mood: () => mood),
          );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleFavorite(String id) =>
      ref.read(entriesProvider.notifier).toggleFavorite(id);

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayEntryProvider);
    final entries = ref.watch(entriesProvider);
    final streaks = ref.watch(streakProvider);
    final prompt = ref.watch(dailyPromptProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(DateFormat('EEEE, d MMMM').format(DateTime.now())),
            Text(
              'Today',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => context.push('/search'),
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Search entries',
          ),
          IconButton(
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Settings',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/entry/new?id=${ref.read(uuidProvider)()}'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New entry'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(entriesProvider);
          await ref.read(entriesProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            if (prompt.isNotEmpty) ...[
              Text(
                prompt,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 14),
            ],
            _TodayCard(
              today: today,
              saving: _saving,
              onPick: _pickMood,
            ),
            const SizedBox(height: 16),
            streaks.when(
              loading: () => const _StreakSkeleton(),
              error: (error, _) => _InlineError(message: '$error'),
              data: (stats) => StreakBanner(stats: stats),
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Text(
                  'Recent entries',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                Text(
                  DateFormat('MMMM yyyy').format(DateTime.now()),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            entries.when(
              loading: () => const _ListSkeleton(),
              error: (error, _) => ErrorRetry(
                error: error,
                onRetry: () => ref.invalidate(entriesProvider),
              ),
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: EmptyState(
                        icon: Icons.wb_twilight_rounded,
                        title: 'Your journal starts here',
                        message:
                            'Tap how you feel above. That is the whole app — '
                            'everything else is just your history.',
                      ),
                    )
                  : Column(
                      children: [
                        for (final entry in list.take(30))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: EntryCard(
                              entry: entry,
                              onTap: () => context.push('/entry/${entry.id}'),
                              onToggleFavorite: () => _toggleFavorite(entry.id),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 5-second interaction. Deliberately not a form.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.today, required this.saving, required this.onPick});

  final AsyncValue<JournalEntry?> today;
  final bool saving;
  final ValueChanged<Mood> onPick;

  @override
  Widget build(BuildContext context) {
    final palette = context.moodPalette;

    return today.when(
      loading: () => const _CardShell(child: _PickerSkeleton()),
      error: (error, _) => _CardShell(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: _InlineError(message: '$error'),
        ),
      ),
      data: (entry) {
        final hasText = entry != null && entry.body.trim().isNotEmpty;

        return _CardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'How are you feeling?',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  if (saving)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (entry != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline_rounded,
                            size: 13, color: palette.mood4),
                        const SizedBox(width: 4),
                        Text(
                          'saved',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: palette.mood4),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 14),
              MoodPicker(selected: entry?.mood, onSelected: onPick),
              if (hasText) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: palette.moodSurface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    entry.body.trim(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(height: 1.45),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => context.push('/entry/${entry.id}'),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Keep writing'),
                  ),
                ),
              ] else if (entry != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => context.push('/entry/${entry.id}'),
                    icon: const Icon(Icons.notes_rounded, size: 16),
                    label: const Text('Add some words'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

class _PickerSkeleton extends StatelessWidget {
  const _PickerSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 5; i++)
          Expanded(
            child: Container(
              height: 68,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
      ],
    );
  }
}

class _StreakSkeleton extends StatelessWidget {
  const _StreakSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 3; i++)
          Expanded(
            child: Container(
              height: 74,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
      ],
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              height: 88,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.error_outline_rounded,
            size: 16, color: Theme.of(context).colorScheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ),
      ],
    );
  }
}
