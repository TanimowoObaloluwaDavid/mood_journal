import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../domain/models/insights_bundle.dart';
import '../../domain/models/mood.dart';
import '../providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/mood_picker.dart';
import '../widgets/streak_banner.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider);
    final streaks = ref.watch(streakProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: insights.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetry(
          error: error,
          onRetry: () => ref.invalidate(insightsProvider),
        ),
        data: (bundle) {
          if (bundle.isEmpty) {
            return const EmptyState(
              icon: Icons.insights_rounded,
              title: 'Nothing to see yet',
              message:
                  'Log your mood for a few days and this page fills up with '
                  'trends, patterns and writing stats.',
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              streaks.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (stats) => StreakBanner(stats: stats),
              ),
              const SizedBox(height: 18),
              _Section(
                title: 'Mood over time',
                subtitle: 'Daily average, most recent ${bundle.dailyAverages.length} days',
                child: _MoodTrendChart(data: bundle.dailyAverages),
              ),
              const SizedBox(height: 14),
              _Section(
                title: 'How often you felt',
                subtitle: 'Days per mood',
                child: _MoodDistributionChart(counts: bundle.moodCounts),
              ),
              if (bundle.moodByWeekday != null) ...[
                const SizedBox(height: 14),
                _Section(
                  title: 'Mood by weekday',
                  subtitle: 'Which days are hardest',
                  child: _WeekdayChart(averages: bundle.moodByWeekday!),
                ),
              ],
              const SizedBox(height: 14),
              _Section(
                title: 'Writing',
                subtitle: 'What you actually wrote',
                child: _WritingStats(bundle: bundle),
              ),
              if (bundle.topTags.isNotEmpty) ...[
                const SizedBox(height: 14),
                _Section(
                  title: 'Top tags',
                  subtitle: 'What keeps coming up',
                  child: _TopTags(tags: bundle.topTags),
                ),
              ],
              if (bundle.longestEntryId != null) ...[
                const SizedBox(height: 14),
                _LongestEntryCard(entryId: bundle.longestEntryId!),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 18),
            SizedBox(height: 180, child: child),
          ],
        ),
      ),
    );
  }
}

/// Line chart of daily average mood.
///
/// The y-axis is pinned to 1..5 rather than auto-scaled: an auto-scaled axis
/// would turn a 3.4 → 4.1 improvement into a dramatic-looking mountain range.
class _MoodTrendChart extends StatelessWidget {
  const _MoodTrendChart({required this.data});

  final List<DailyAverage> data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visible = data.length > 90 ? data.sublist(data.length - 90) : data;

    final spots = <FlSpot>[
      for (var i = 0; i < visible.length; i++)
        FlSpot(i.toDouble(), visible[i].average),
    ];

    return LineChart(
      LineChartData(
        minY: 1,
        maxY: 5,
        minX: 0,
        maxX: (visible.length - 1).toDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 1,
          getDrawingHorizontalLine: (value) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 34,
              getTitlesWidget: (value, _) {
                final mood = Mood.fromValue(value.round());
                if (mood == null) return const SizedBox.shrink();
                return Text(
                  mood.emoji,
                  style: const TextStyle(fontSize: 12),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (visible.length / 4).ceilToDouble().clamp(1, 999),
              reservedSize: 26,
              getTitlesWidget: (value, _) {
                final index = value.round();
                if (index < 0 || index >= visible.length) {
                  return const SizedBox.shrink();
                }

                // The first and last labels are centred on the plot's edges,
                // so half of each would be clipped. Anchoring them inward
                // inside a fixed-width box keeps them fully readable.
                final isFirst = index == 0;
                final isLast = index == visible.length - 1;

                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: 48,
                    child: Align(
                      alignment: isFirst
                          ? Alignment.centerLeft
                          : isLast
                              ? Alignment.centerRight
                              : Alignment.center,
                      child: Text(
                        DateFormat('d MMM').format(visible[index].date),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((spot) {
              final mood = Mood.fromAverage(spot.y);
              final index = spot.x.round().clamp(0, visible.length - 1);
              return LineTooltipItem(
                '${mood.emoji} ${mood.label}\n'
                '${DateFormat('EEE d MMM').format(visible[index].date)}',
                TextStyle(
                  color: scheme.onInverseSurface,
                  fontWeight: FontWeight.w600,
                ),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: scheme.primary,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: scheme.primary.withValues(alpha: 0.10),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodDistributionChart extends StatelessWidget {
  const _MoodDistributionChart({required this.counts});

  final Map<Mood, int> counts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = counts.values.fold<int>(0, (sum, value) => sum + value);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 110,
          height: 110,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 30,
              sections: [
                for (final mood in Mood.values)
                  if ((counts[mood] ?? 0) > 0)
                    PieChartSectionData(
                      value: counts[mood]!.toDouble(),
                      color: mood.color(context),
                      radius: 22,
                      showTitle: false,
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final mood in Mood.values)
                if ((counts[mood] ?? 0) > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Text(mood.emoji, style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            mood.label,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Text(
                          '${(counts[mood]! * 100 / total).round()}%',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WeekdayChart extends StatelessWidget {
  const _WeekdayChart({required this.averages});

  final Map<int, double> averages;

  static const _labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return BarChart(
      BarChartData(
        minY: 1,
        maxY: 5,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 1,
          getDrawingHorizontalLine: (value) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 1 || index > 7) return const SizedBox.shrink();
                return Text(
                  _labels[index - 1],
                  style: Theme.of(context).textTheme.labelSmall,
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final mood = Mood.fromAverage(rod.toY);
              return BarTooltipItem(
                '${_labels[group.x - 1]}\n${mood.emoji} ${mood.label}',
                TextStyle(color: scheme.onInverseSurface),
              );
            },
          ),
        ),
        barGroups: [
          for (var day = 1; day <= 7; day++)
            BarChartGroupData(
              x: day,
              barRods: [
                if (averages[day] != null)
                  BarChartRodData(
                    toY: averages[day]!,
                    width: 16,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(6),
                    ),
                    color: Mood.fromAverage(averages[day]!).color(context),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _WritingStats extends StatelessWidget {
  const _WritingStats({required this.bundle});

  final InsightsBundle bundle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _StatTile(
          label: 'Total words',
          value: _compact(bundle.totalWords),
          icon: Icons.notes_rounded,
        ),
        _StatTile(
          label: 'Entries',
          value: '${bundle.totalEntries}',
          icon: Icons.auto_stories_rounded,
        ),
        _StatTile(
          label: 'Avg words/entry',
          value: '${bundle.averageWordsPerEntry.round()}',
          icon: Icons.straighten_rounded,
        ),
        _StatTile(
          label: 'This month',
          value: '${bundle.entriesThisMonth}',
          icon: Icons.calendar_month_rounded,
        ),
      ],
    );
  }

  static String _compact(int value) {
    if (value < 1000) return '$value';
    return '${(value / 1000).toStringAsFixed(1)}k';
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: (MediaQuery.sizeOf(context).width - 32 - 32 - 10) / 2,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(height: 10),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800, height: 1),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _TopTags extends StatelessWidget {
  const _TopTags({required this.tags});

  final List<MapEntry<String, int>> tags;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tag in tags)
          MoodChip(
            label: '#${tag.key} · ${tag.value}',
            icon: Icons.tag_rounded,
          ),
      ],
    );
  }
}

/// Teaser that links to the user's longest entry — a cheap way to reward
/// writing more than a number does.
class _LongestEntryCard extends StatelessWidget {
  const _LongestEntryCard({required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.auto_awesome_rounded),
        title: const Text('Your longest entry'),
        subtitle: const Text('You wrote a lot on a good day.'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/entry/$entryId'),
      ),
    );
  }
}
