import 'package:flutter/material.dart';

/// Colour tokens for the five moods.
///
/// Moods are never conveyed by colour alone — the emoji and the text label always
/// carry the meaning too. These colours only reinforce it (WCAG 1.4.1).
@immutable
class MoodPalette extends ThemeExtension<MoodPalette> {
  const MoodPalette({
    required this.mood1,
    required this.mood2,
    required this.mood3,
    required this.mood4,
    required this.mood5,
    required this.moodSurface,
    required this.moodSurfaceStrong,
  });

  /// 😢 Bad
  final Color mood1;

  /// 😟 Low
  final Color mood2;

  /// 😐 Okay
  final Color mood3;

  /// 🙂 Good
  final Color mood4;

  /// 😄 Great
  final Color mood5;

  final Color moodSurface;
  final Color moodSurfaceStrong;

  static const light = MoodPalette(
    mood1: Color(0xFFE05A6A),
    mood2: Color(0xFFEF8A5B),
    mood3: Color(0xFFE8B84B),
    mood4: Color(0xFF4FB6A8),
    mood5: Color(0xFF5BAE6A),
    moodSurface: Color(0xFFF2F1F7),
    moodSurfaceStrong: Color(0xFFE4E2EE),
  );

  static const dark = MoodPalette(
    mood1: Color(0xFFF0707E),
    mood2: Color(0xFFF7A176),
    mood3: Color(0xFFF0C761),
    mood4: Color(0xFF63CDBE),
    mood5: Color(0xFF72C582),
    moodSurface: Color(0xFF23222B),
    moodSurfaceStrong: Color(0xFF2F2D3A),
  );

  @override
  MoodPalette copyWith({
    Color? mood1,
    Color? mood2,
    Color? mood3,
    Color? mood4,
    Color? mood5,
    Color? moodSurface,
    Color? moodSurfaceStrong,
  }) {
    return MoodPalette(
      mood1: mood1 ?? this.mood1,
      mood2: mood2 ?? this.mood2,
      mood3: mood3 ?? this.mood3,
      mood4: mood4 ?? this.mood4,
      mood5: mood5 ?? this.mood5,
      moodSurface: moodSurface ?? this.moodSurface,
      moodSurfaceStrong: moodSurfaceStrong ?? this.moodSurfaceStrong,
    );
  }

  @override
  MoodPalette lerp(ThemeExtension<MoodPalette>? other, double t) {
    if (other is! MoodPalette) return this;
    return MoodPalette(
      mood1: Color.lerp(mood1, other.mood1, t)!,
      mood2: Color.lerp(mood2, other.mood2, t)!,
      mood3: Color.lerp(mood3, other.mood3, t)!,
      mood4: Color.lerp(mood4, other.mood4, t)!,
      mood5: Color.lerp(mood5, other.mood5, t)!,
      moodSurface: Color.lerp(moodSurface, other.moodSurface, t)!,
      moodSurfaceStrong: Color.lerp(moodSurfaceStrong, other.moodSurfaceStrong, t)!,
    );
  }
}

/// Reads the palette without force-unwrapping.
///
/// A widget must never crash because a theme forgot to register the extension
/// — an unstyled widget in a test, a dialog, or a future screen would take the
/// whole app down over a colour. Falls back to the static palette for the
/// current brightness instead.
extension MoodPaletteOf on BuildContext {
  MoodPalette get moodPalette {
    final theme = Theme.of(this);
    return theme.extension<MoodPalette>() ??
        (theme.brightness == Brightness.dark
            ? MoodPalette.dark
            : MoodPalette.light);
  }
}
