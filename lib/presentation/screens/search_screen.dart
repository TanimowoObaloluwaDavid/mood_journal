import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/entry_card.dart';

/// 150 ms is the sweet spot: long enough that typing a word produces one
/// decrypt pass, short enough that results feel live.
const _debounce = Duration(milliseconds: 150);

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      ref.read(searchQueryProvider.notifier).update(value);
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text;
    final results = ref.watch(searchResultsProvider(query));

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search entries and tags',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _controller.clear();
                      ref.read(searchQueryProvider.notifier).clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
      ),
      body: query.trim().isEmpty
          ? const EmptyState(
              icon: Icons.search_rounded,
              title: 'Find anything you wrote',
              message:
                  'Searches the text of your entries and the tags you have '
                  'used. Everything runs on this device.',
            )
          : results.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => ErrorRetry(
                error: error,
                onRetry: () => ref.invalidate(searchResultsProvider(query)),
              ),
              data: (list) => list.isEmpty
                  ? EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No matches for "$query"',
                      message: 'Try a different word, or a tag you have used before.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final entry = list[index];
                        return EntryCard(
                          entry: entry,
                          onTap: () => context.push('/entry/${entry.id}'),
                          onToggleFavorite: () => ref
                              .read(entriesProvider.notifier)
                              .toggleFavorite(entry.id),
                        );
                      },
                    ),
            ),
    );
  }
}
