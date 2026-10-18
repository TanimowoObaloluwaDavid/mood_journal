import 'package:flutter_test/flutter_test.dart';
import 'package:mood_journal/domain/models/journal_entry.dart';

void main() {
  JournalEntry entry({String? title, String body = ''}) => JournalEntry(
        id: 'a',
        title: title,
        body: body,
        prompt: null,
        entryDate: DateTime(2026, 10, 17),
        mood: null,
        energy: null,
        wordCount: 0,
        isFavorite: false,
        createdAt: DateTime(2026, 10, 17),
        updatedAt: DateTime(2026, 10, 17),
      );

  group('displayTitle', () {
    test('uses an explicit title when there is one', () {
      expect(entry(title: 'A real title', body: 'something else').displayTitle,
          'A real title');
    });

    test('falls back to the opening words of the body', () {
      final long = 'one two three four five six seven eight';
      expect(entry(body: long).displayTitle, 'one two three four five six…');
    });

    test('shows the whole body when it is short', () {
      expect(entry(body: 'short enough').displayTitle, 'short enough');
    });

    test('never returns an empty string', () {
      expect(entry().displayTitle, 'Untitled entry');
      expect(entry(body: '   ').displayTitle, 'Untitled entry');
    });
  });

  group('hasExplicitTitle', () {
    test('is true only for a user-set title', () {
      expect(entry(title: 'Real').hasExplicitTitle, isTrue);
      expect(entry(title: '   ').hasExplicitTitle, isFalse,
          reason: 'whitespace is not a title');
      expect(entry(title: null, body: 'text').hasExplicitTitle, isFalse);
      expect(entry().hasExplicitTitle, isFalse);
    });

    test('guards the list row against printing the body twice', () {
      // Regression: the timeline showed the derived title *and* the same
      // opening words again as the preview underneath it.
      const body = 'quiet day nothing much happened and that was fine';
      final derived = entry(body: body);

      expect(derived.hasExplicitTitle, isFalse);
      expect(derived.displayTitle, 'quiet day nothing much happened and…');
    });
  });
}
