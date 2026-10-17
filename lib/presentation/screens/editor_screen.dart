import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/day_utils.dart';
import '../../domain/models/journal_entry.dart';
import '../../domain/models/mood.dart';
import '../providers.dart';
import '../widgets/mood_picker.dart';

const _uuid = Uuid();

/// Debounce for autosave. Long enough that a fast typist produces one write,
/// short enough that putting the phone down mid-sentence still persists.
const _autosaveDelay = Duration(milliseconds: 800);

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key, required this.entryId, this.seedDate});

  /// Empty string means "not created yet" — the id is minted on first save.
  final String entryId;
  final DateTime? seedDate;

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final _bodyController = TextEditingController();
  final _tagController = TextEditingController();
  final _focusNode = FocusNode();

  Timer? _debounce;
  JournalEntry _entry = JournalEntry.empty(id: '');
  List<Tag> _tags = const [];
  bool _loaded = false;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // A pending autosave still fires: losing the last sentence because the
    // user hit back would be the worst bug in a journal.
    _flush();
    _debounce?.cancel();
    _bodyController.dispose();
    _tagController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.entryId.isEmpty ? _uuid.v4() : widget.entryId;

    final existing = await ref.read(journalRepositoryProvider).getEntryById(id);
    final entry = existing ??
        JournalEntry.empty(
          id: id,
          date: widget.seedDate,
          prompt: ref.read(dailyPromptProvider),
        );

    final tags = existing?.tags ?? const <Tag>[];

    if (!mounted) return;
    setState(() {
      _entry = entry;
      _tags = tags;
      _bodyController.text = entry.body;
      _tagController.text = tags.map((t) => t.name).join(', ');
      _loaded = true;
    });

    if (existing == null && widget.seedDate == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  void _onBodyChanged(String value) {
    setState(() {
      _entry = _entry.copyWith(body: value);
      _dirty = true;
    });
    _scheduleSave();
  }

  void _onMoodSelected(Mood mood) {
    setState(() {
      _entry = _entry.copyWith(mood: () => mood);
      _dirty = true;
    });
    // A mood tap is worth persisting immediately — the user may close the app
    // straight after tapping and expect that to count.
    _scheduleSave();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(_autosaveDelay, _flush);
  }

  Future<void> _flush() async {
    if (!_dirty || _saving) return;
    _saving = true;
    _dirty = false;

    final toSave = _entry.copyWith(tags: _parsedTags());
    try {
      await ref.read(entriesProvider.notifier).save(toSave);
    } catch (error) {
      // Put the flag back so the next keystroke retries rather than silently
      // dropping the text.
      if (mounted) {
        setState(() => _dirty = true);
        _showError(error);
      }
    } finally {
      _saving = false;
    }
  }

  List<Tag> _parsedTags() {
    final names = _tagController.text
        .split(',')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty);

    final seen = <String>{};
    return [
      for (final name in names)
        if (seen.add(name.toLowerCase())) Tag(id: name.toLowerCase(), name: name),
    ];
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not save: $error')),
    );
  }

  Future<void> _changeDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _entry.entryDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _entry = _entry.copyWith(entryDate: startOfDay(picked));
      _dirty = true;
    });
    _scheduleSave();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    _debounce?.cancel();
    await ref.read(entriesProvider.notifier).remove(_entry.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_loaded ? _dateLabel(_entry.entryDate) : 'Loading…'),
        actions: [
          IconButton(
            onPressed: _loaded ? _changeDate : null,
            icon: const Icon(Icons.event_rounded),
            tooltip: 'Change date',
          ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') _delete();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'favorite',
                onTap: () => setState(() {
                  _entry = _entry.copyWith(isFavorite: !_entry.isFavorite);
                  _dirty = true;
                }),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _entry.isFavorite
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                  ),
                  title: Text(
                    _entry.isFavorite ? 'Unfavourite' : 'Favourite',
                  ),
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 60),
              children: [
                if (_entry.prompt != null && _entry.prompt!.isNotEmpty) ...[
                  Text(
                    _entry.prompt!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                  const SizedBox(height: 16),
                ],
                MoodPicker(
                  selected: _entry.mood,
                  onSelected: _onMoodSelected,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _bodyController,
                  focusNode: _focusNode,
                  onChanged: _onBodyChanged,
                  maxLines: null,
                  minLines: 8,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(height: 1.6),
                  decoration: const InputDecoration(
                    hintText: 'What happened today?',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _tagController,
                  onChanged: (_) {
                    setState(() {
                      _tags = _parsedTags();
                      _dirty = true;
                    });
                    _scheduleSave();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    hintText: 'work, family, sleep',
                    prefixIcon: Icon(Icons.sell_outlined, size: 20),
                  ),
                ),
                if (_tags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in _tags) MoodChip(label: '#${tag.name}'),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                _WordCount(count: countWords(_bodyController.text)),
              ],
            ),
    );
  }

  String _dateLabel(DateTime date) {
    final today = startOfToday();
    if (daysBetween(date, today) == 0) return 'Today';
    if (daysBetween(date, today) == -1) return 'Yesterday';
    return DateFormat('EEEE, d MMMM').format(date);
  }
}

class _WordCount extends StatelessWidget {
  const _WordCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Text(
      count == 0 ? 'Autosaves as you type' : '$count ${count == 1 ? 'word' : 'words'}',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}
