import '../../core/utils/day_utils.dart';
import 'mood.dart';

/// A journal entry, decrypted and ready for the UI.
///
/// This is the domain model; `JournalEntriesCompanion` is the database row and
/// the two are deliberately separate so encryption can live in the mapper.
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.entryDate,
    required this.mood,
    required this.energy,
    required this.wordCount,
    required this.isFavorite,
    required this.createdAt,
    required this.updatedAt,
    this.prompt,
    this.tags = const [],
  });

  final String id;
  final String? title;
  final String body;

  /// The optional prompt shown when this entry was created.
  final String? prompt;

  /// Midnight local. Multiple entries can share a day.
  final DateTime entryDate;

  final Mood? mood;
  final int? energy;
  final int wordCount;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Tag> tags;

  bool get isEmpty => body.trim().isEmpty && tags.isEmpty;

  /// True when the user set a title of their own, as opposed to one derived
  /// from the body by [displayTitle].
  ///
  /// List rows use this to decide whether to show a body preview: when the
  /// title *is* the opening of the body, previewing the body underneath just
  /// prints the same sentence twice.
  bool get hasExplicitTitle => title?.trim().isNotEmpty ?? false;

  /// A human-readable heading. Falls back to the first few words of the body,
  /// so a list never shows a wall of empty titles.
  String get displayTitle {
    final explicit = title?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    final words = body.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return 'Untitled entry';
    if (words.length <= 6) return body.trim();
    return '${words.take(6).join(' ')}…';
  }

  JournalEntry copyWith({
    String? title,
    String? body,
    String? Function()? prompt,
    DateTime? entryDate,
    Mood? Function()? mood,
    int? Function()? energy,
    int? wordCount,
    bool? isFavorite,
    DateTime? updatedAt,
    List<Tag>? tags,
  }) {
    return JournalEntry(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      prompt: prompt != null ? prompt() : this.prompt,
      entryDate: entryDate ?? this.entryDate,
      mood: mood != null ? mood() : this.mood,
      energy: energy != null ? energy() : this.energy,
      wordCount: wordCount ?? this.wordCount,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
    );
  }

  static JournalEntry empty({
    required String id,
    DateTime? date,
    String? prompt,
    Mood? mood,
  }) {
    final now = DateTime.now();
    return JournalEntry(
      id: id,
      title: null,
      body: '',
      prompt: prompt,
      entryDate: startOfDay(date ?? now),
      mood: mood,
      energy: null,
      wordCount: 0,
      isFavorite: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is JournalEntry &&
      other.id == id &&
      other.body == body &&
      other.title == title &&
      other.mood == mood &&
      other.energy == energy &&
      other.isFavorite == isFavorite &&
      other.entryDate == entryDate &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        body,
        title,
        mood,
        energy,
        isFavorite,
        entryDate,
        updatedAt,
      );
}

class Tag {
  const Tag({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) => other is Tag && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
