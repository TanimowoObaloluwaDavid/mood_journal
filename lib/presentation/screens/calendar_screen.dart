import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/mood_palette.dart';
import '../../core/utils/day_utils.dart';
import '../../domain/models/mood.dart';
import '../../domain/models/stats.dart';
import '../providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/entry_card.dart';

class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heatmap = ref.watch(heatmapProvider);
    final entries = ref.watch(entriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: heatmap.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetry(
          error: error,
          onRetry: () => ref.invalidate(heatmapProvider),
        ),
        data: (days) {
          if (days.every((day) => !day.hasData)) {
            return const EmptyState(
              icon: Icons.calendar_month_outlined,
              title: 'Nothing logged yet',
              message:
                  'Once you record a few days, this fills with your mood '
                  'history — one square per day.',
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              const _HeatmapLegend(),
              const SizedBox(height: 18),
              _Heatmap(days: days),
              const SizedBox(height: 26),
              Text(
                'This month',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              entries.when(
                loading: () => const SizedBox.shrink(),
                error: (error, _) => Text('$error'),
                data: (list) {
                  final now = DateTime.now();
                  final monthly = list
                      .where((entry) =>
                          entry.entryDate.year == now.year &&
                          entry.entryDate.month == now.month)
                      .toList();

                  if (monthly.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No entries this month yet.'),
                    );
                  }

                  return Column(
                    children: [
                      for (final entry in monthly)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: EntryCard(
                            entry: entry,
                            onTap: () => context.push('/entry/${entry.id}'),
                            onToggleFavorite: () => ref
                                .read(entriesProvider.notifier)
                                .toggleFavorite(entry.id),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeatmapLegend extends StatelessWidget {
  const _HeatmapLegend();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Last 26 weeks',
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const Spacer(),
        Text('Awful', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(width: 5),
        for (final mood in Mood.values.reversed)
          Container(
            width: 13,
            height: 13,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: mood.color(context),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        Text('Great', style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// GitHub-style contribution grid: one column per week, one cell per day.
///
/// Rendered as a horizontal scroll view because 26 columns of fixed width do
/// not fit a phone, and squeezing them would make the cells untappable.
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.days});

  final List<DayMood> days;

  static const _cell = 15.0;
  static const _gap = 3.5;

  @override
  Widget build(BuildContext context) {
    final palette = context.moodPalette;

    // Pad the front so the first column starts on a Monday.
    final first = days.isEmpty ? startOfToday() : days.first.date;
    final leadingBlanks = first.weekday - DateTime.monday;
    final slots = <DayMood?>[
      ...List<DayMood?>.filled(leadingBlanks, null),
      ...days,
    ];

    final columns = <List<DayMood?>>[];
    for (var i = 0; i < slots.length; i += 7) {
      columns.add(slots.sublist(i, (i + 7).clamp(0, slots.length)));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var column = 0; column < columns.length; column++)
            Padding(
              padding: const EdgeInsets.only(right: _gap),
              child: Column(
                children: [
                  for (var row = 0; row < 7; row++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: _gap),
                      child: _Cell(
                        day: column * 7 + row < slots.length
                            ? slots[column * 7 + row]
                            : null,
                        palette: palette,
                        size: _cell,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.day, required this.palette, required this.size});

  final DayMood? day;
  final MoodPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    final data = day;

    if (data == null) {
      return SizedBox(width: size, height: size);
    }

    if (!data.hasData) {
      return Tooltip(
        message: DateFormat('d MMM yyyy').format(data.date),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: palette.moodSurface,
            borderRadius: BorderRadius.circular(3.5),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 0.5,
            ),
          ),
        ),
      );
    }

    final mood = Mood.fromAverage(data.average!);
    final label =
        '${DateFormat('EEEE d MMMM').format(data.date)}, mood ${mood.label.toLowerCase()}';

    return Semantics(
      label: label,
      button: true,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(3.5),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: mood.color(context),
              borderRadius: BorderRadius.circular(3.5),
            ),
          ),
        ),
      ),
    );
  }

  /// Jumps to that day's existing entry, or offers to create one.
  void _open(BuildContext context) {
    final date = day!.date;
    context.push(
      '/entry/new?id=${const Uuid().v4()}&date=${date.toIso8601String()}',
    );
  }
}
