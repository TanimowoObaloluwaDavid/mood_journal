import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mood_journal/core/theme/app_theme.dart';
import 'package:mood_journal/domain/models/mood.dart';
import 'package:mood_journal/presentation/widgets/mood_picker.dart';

void main() {
  // Uses the app's real theme so the test exercises the same palette
  // extension the app registers at runtime.
  Widget host(Mood? selected, ValueChanged<Mood> onSelected) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: MoodPicker(selected: selected, onSelected: onSelected),
        ),
      ),
    );
  }

  Widget plain(Mood? mood) {
    return MaterialApp(
      home: Scaffold(body: MoodDot(mood: mood, size: 44)),
    );
  }

  group('MoodPicker', () {
    testWidgets('renders all five moods', (tester) async {
      await tester.pumpWidget(host(null, (_) {}));

      for (final mood in Mood.values) {
        expect(find.text(mood.emoji), findsOneWidget, reason: mood.label);
        expect(find.text(mood.label), findsOneWidget, reason: mood.label);
      }
    });

    testWidgets('reports the tapped mood', (tester) async {
      Mood? tapped;
      await tester.pumpWidget(host(null, (mood) => tapped = mood));

      await tester.tap(find.text(Mood.great.emoji));
      await tester.pump();

      expect(tapped, Mood.great);
    });

    testWidgets('the selected mood is exposed to screen readers as selected',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(Mood.good, (_) {}));

      final semantics = tester.getSemantics(find.bySemanticsLabel('Mood: Good'));
      expect(
        semantics.flagsCollection.isSelected,
        isNot(Tristate.isFalse),
        reason: 'selection must be announced, not only coloured',
      );

      // Meaning must not depend on colour: the label carries it too.
      expect(find.text('Good'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('every mood control has a semantic label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(null, (_) {}));

      for (final mood in Mood.values) {
        expect(find.bySemanticsLabel(mood.semanticLabel), findsOneWidget);
      }
      handle.dispose();
    });

    testWidgets('tapping a different mood fires again', (tester) async {
      final tapped = <Mood>[];
      await tester.pumpWidget(host(Mood.okay, tapped.add));

      await tester.tap(find.text(Mood.low.emoji));
      await tester.pump();
      await tester.tap(find.text(Mood.good.emoji));
      await tester.pump();

      expect(tapped, [Mood.low, Mood.good]);
    });
  });

  group('MoodDot', () {
    testWidgets('shows a dash for an entry with no mood', (tester) async {
      await tester.pumpWidget(plain(null));
      expect(find.byIcon(Icons.remove), findsOneWidget);
    });

    testWidgets('shows the emoji when a mood is set', (tester) async {
      await tester.pumpWidget(plain(Mood.great));
      expect(find.text('😄'), findsOneWidget);
    });

    testWidgets('survives a theme that has no mood palette registered',
        (tester) async {
      // Regression guard: the palette lookup used to be force-unwrapped, so a
      // bare MaterialApp crashed the widget instead of falling back.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: MoodDot(mood: Mood.good))),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('🙂'), findsOneWidget);
    });
  });
}
