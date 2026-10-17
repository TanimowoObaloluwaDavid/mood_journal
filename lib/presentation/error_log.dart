import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Last 100 unhandled errors, newest first.
///
/// A journal holds someone's private thoughts. A crash loop that silently
/// discards an autosave is a data-loss bug, so errors are recorded rather than
/// swallowed, and surfaced on Settings → Diagnostics.
class ErrorLog {
  final List<String> _entries = [];
  static const _capacity = 100;

  void add(String message) {
    _entries.add(message);
    if (_entries.length > _capacity) _entries.removeAt(0);
    if (kDebugMode) debugPrint('[mood_journal] $message');
  }

  List<String> get entries => List.unmodifiable(_entries.reversed);

  bool get isEmpty => _entries.isEmpty;

  void clear() => _entries.clear();
}

final errorLogProvider = Provider<ErrorLog>((ref) => ErrorLog());
