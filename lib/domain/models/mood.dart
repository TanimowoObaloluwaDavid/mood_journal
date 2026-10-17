import 'package:flutter/material.dart';

import '../../core/theme/mood_palette.dart';

/// The five moods, stored as ints 1–5 so that averaging is meaningful.
///
/// Storing these as strings ("good", "great") would make every chart in the app
/// need a lookup table, and would make "worst mood this month" ambiguous.
enum Mood {
  awful(1, '😢', 'Awful'),
  low(2, '😟', 'Low'),
  okay(3, '😐', 'Okay'),
  good(4, '🙂', 'Good'),
  great(5, '😄', 'Great');

  const Mood(this.value, this.emoji, this.label);

  final int value;
  final String emoji;
  final String label;

  /// Safest possible mood, used as a chart-domain bound.
  static const minValue = 1;
  static const maxValue = 5;

  /// `null` for anything out of range, so bad data never crashes a chart.
  static Mood? fromValue(int? value) {
    if (value == null) return null;
    for (final mood in Mood.values) {
      if (mood.value == value) return mood;
    }
    return null;
  }

  /// Maps an average (e.g. 3.6) back to the nearest whole mood.
  static Mood fromAverage(double average) {
    final rounded = average.round().clamp(minValue, maxValue);
    return fromValue(rounded)!;
  }

  Color color(BuildContext context) {
    final palette = context.moodPalette;
    return switch (this) {
      Mood.awful => palette.mood1,
      Mood.low => palette.mood2,
      Mood.okay => palette.mood3,
      Mood.good => palette.mood4,
      Mood.great => palette.mood5,
    };
  }

  /// Muted background for chips and heatmap cells.
  Color surface(BuildContext context) => color(context).withValues(alpha: 0.12);

  /// A screen reader hears "Mood, Good" — never just "smiling face".
  String get semanticLabel => 'Mood: $label';
}
