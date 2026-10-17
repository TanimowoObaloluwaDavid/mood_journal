import 'package:flutter/material.dart';

import '../../core/theme/mood_palette.dart';
import '../../domain/models/mood.dart';

/// The five-mood selector.
///
/// One tap is the whole interaction: no save button, no dropdown. The selected
/// state is shown by fill + a check, never by colour alone, so it still reads
/// correctly in greyscale and to a screen reader.
class MoodPicker extends StatelessWidget {
  const MoodPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    this.compact = false,
  });

  final Mood? selected;
  final ValueChanged<Mood> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.moodPalette;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final mood in Mood.values)
          Expanded(
            child: Semantics(
              // One clean node per control.
              //
              // `container: true` stops the label from being hoisted onto the
              // surrounding Row, and `excludeSemantics: true` stops the
              // InkWell from creating a *second*, unlabelled node for the tap.
              // The tap action is therefore declared here, on the same node
              // that carries the label and the selected state — otherwise a
              // screen reader would focus an unlabelled button.
              container: true,
              excludeSemantics: true,
              label: mood.semanticLabel,
              selected: selected == mood,
              button: true,
              onTap: () => onSelected(mood),
              child: InkWell(
                onTap: () => onSelected(mood),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.symmetric(vertical: compact ? 10 : 14),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: selected == mood
                        ? mood.color(context).withValues(alpha: 0.16)
                        : palette.moodSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected == mood
                          ? mood.color(context)
                          : Colors.transparent,
                      width: 1.8,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Decorative: the parent already says "Mood: Good", so
                      // announcing "smiling face" too would just be noise.
                      Text(
                        mood.emoji,
                        style: TextStyle(fontSize: compact ? 22 : 28),
                      ),
                      const SizedBox(height: 6),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 180),
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                              fontSize: compact ? 10 : 11,
                              fontWeight: selected == mood
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selected == mood
                                  ? mood.color(context)
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                            ),
                        child: Text(mood.label),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Small inline mood indicator for list rows.
class MoodDot extends StatelessWidget {
  const MoodDot({super.key, required this.mood, this.size = 40});

  final Mood? mood;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (mood == null) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.remove,
          size: size * 0.4,
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: mood!.surface(context),
        shape: BoxShape.circle,
      ),
      child: Text(mood!.emoji, style: TextStyle(fontSize: size * 0.5)),
    );
  }
}

/// A rounded label, used for tags on entries and in Insights.
class MoodChip extends StatelessWidget {
  const MoodChip({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.onTap,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? scheme.primary;

    return Semantics(
      button: onTap != null,
      label: label,
      child: Material(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: tint),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tint,
                        fontWeight: FontWeight.w600,
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
