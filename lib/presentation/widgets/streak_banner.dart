import 'package:flutter/material.dart';

import '../../domain/models/stats.dart';

/// Streak header: current streak, longest, and total days logged.
class StreakBanner extends StatelessWidget {
  const StreakBanner({super.key, required this.stats});

  final StreakStats stats;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Stat(
            icon: Icons.local_fire_department_rounded,
            value: '${stats.current}',
            label: stats.current == 1 ? 'day streak' : 'day streak',
            tint: const Color(0xFFEF8A5B),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Stat(
            icon: Icons.emoji_events_outlined,
            value: '${stats.longest}',
            label: 'best',
            tint: const Color(0xFFE8B84B),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Stat(
            icon: Icons.calendar_month_rounded,
            value: '${stats.totalDays}',
            label: 'days logged',
            tint: const Color(0xFF6C5CE7),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.value,
    required this.label,
    required this.tint,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$value $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: tint),
            const SizedBox(height: 5),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: tint,
                    height: 1,
                  ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
