import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/models/journal_entry.dart';
import 'mood_picker.dart';

/// One row in the timeline.
class EntryCard extends StatelessWidget {
  const EntryCard({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onToggleFavorite,
    this.showDate = true,
  });

  final JournalEntry entry;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final isToday = entry.entryDate.year == today.year &&
        entry.entryDate.month == today.month &&
        entry.entryDate.day == today.day;

    final dateLabel = isToday
        ? 'Today'
        : entry.entryDate.year == today.year
            ? DateFormat('EEEE, d MMM').format(entry.entryDate)
            : DateFormat('d MMM yyyy').format(entry.entryDate);

    return Semantics(
      button: true,
      label: '$dateLabel. ${entry.mood?.label ?? 'No mood'}. ${entry.displayTitle}',
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MoodDot(mood: entry.mood, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (showDate)
                            Text(
                              dateLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.2,
                                  ),
                            ),
                          if (entry.isFavorite) ...[
                            if (showDate) const SizedBox(width: 6),
                            Icon(Icons.star_rounded,
                                size: 13, color: scheme.tertiary),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        entry.displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600, height: 1.3),
                      ),
                      // Only preview the body when it adds something. When
                      // there is no explicit title, `displayTitle` is already
                      // the opening of the body, and showing both would print
                      // the same words twice.
                      if (entry.hasExplicitTitle && entry.body.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          entry.body.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                        ),
                      ],
                      if (entry.tags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final tag in entry.tags.take(3))
                              MoodChip(label: '#${tag.name}'),
                            if (entry.tags.length > 3)
                              MoodChip(label: '+${entry.tags.length - 3}'),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onToggleFavorite,
                  visualDensity: VisualDensity.compact,
                  tooltip: entry.isFavorite
                      ? 'Remove from favourites'
                      : 'Add to favourites',
                  icon: Icon(
                    entry.isFavorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 20,
                    color: entry.isFavorite
                        ? scheme.tertiary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.6),
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
