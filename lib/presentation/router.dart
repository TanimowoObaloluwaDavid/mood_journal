import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'screens/calendar_screen.dart';
import 'screens/editor_screen.dart';
import 'screens/home_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';

/// The root navigator.
///
/// Owned by the [GoRouter] below and referenced by every route that sits
/// outside the shell. Without it those routes declare a `parentNavigatorKey`
/// attached to no Navigator, and go_router cannot build them.
final _rootKey = GlobalKey<NavigatorState>();

class ShellScaffold extends StatelessWidget {
  const ShellScaffold({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  int get _index => switch (location) {
        '/calendar' => 1,
        '/insights' => 2,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) {
          final path = switch (index) {
            1 => '/calendar',
            2 => '/insights',
            _ => '/',
          };
          if (path != location) context.go(path);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories_rounded),
            label: 'Journal',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Insights',
          ),
        ],
      ),
    );
  }
}

/// Routes that take over the whole screen live *outside* the [ShellRoute].
///
/// Declaring them as ShellRoute children with a `parentNavigatorKey` looks
/// equivalent and is a trap: on a cold load of such a URL — someone pasting a
/// deep link, or a refresh — go_router builds a navigator stack that leaves
/// the screen blank. As siblings they behave exactly like the editor routes.
final router = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/',
  routes: [
    // The three tabs, which keep the bottom bar and each other's state.
    ShellRoute(
      builder: (context, state, child) => ShellScaffold(
        location: state.matchedLocation,
        child: child,
      ),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
        GoRoute(path: '/calendar', builder: (_, __) => const CalendarScreen()),
        GoRoute(path: '/insights', builder: (_, __) => const InsightsScreen()),
      ],
    ),

    GoRoute(
      path: '/search',
      parentNavigatorKey: _rootKey,
      builder: (_, __) => const SearchScreen(),
    ),
    GoRoute(
      path: '/settings',
      parentNavigatorKey: _rootKey,
      builder: (_, __) => const SettingsScreen(),
    ),

    // `/entry/new` mints an id immediately so autosave has a target from the
    // first keystroke — creating on save would lose everything typed if the
    // process died first. The id arrives as `?id=` from the caller.
    GoRoute(
      path: '/entry/new',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => EditorScreen(
        entryId: state.uri.queryParameters['id'] ?? '',
        seedDate: DateTime.tryParse(state.uri.queryParameters['date'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/entry/:id',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => EditorScreen(
        entryId: state.pathParameters['id']!,
      ),
    ),
  ],
);
