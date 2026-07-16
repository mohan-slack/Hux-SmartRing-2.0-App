/// The app's top-level shell: bottom navigation across Today, Trends,
/// Story, and Modes. The demo banner is pinned here, above all four
/// tabs — a single, unmissable element rather than four copies that
/// could drift out of sync. Each tab keeps its own state when you
/// switch away and back (IndexedStack builds every tab once and keeps
/// them alive, rather than disposing and rebuilding on every switch).

import 'package:flutter/material.dart';

import '../core/meaning/readout_service.dart';
import '../core/meaning/weekly_story.dart';
import '../core/modes/mode_service.dart';
import '../core/storage/health_store.dart';
import '../core/sync/sync_service.dart';
import 'modes_screen.dart';
import 'story_screen.dart';
import 'today_screen.dart';
import 'trends_screen.dart';

class AppShell extends StatefulWidget {
  final HealthStore store;
  final SyncService syncService;
  final ReadoutService readoutService;
  final WeeklyStoryService storyService;
  final ModeService modeService;

  const AppShell({
    super.key,
    required this.store,
    required this.syncService,
    required this.readoutService,
    required this.storyService,
    required this.modeService,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  /// IndexedStack keeps Today's State alive when you switch away —
  /// that's the point, tab state survives. But it also means Today
  /// never re-reads the store on its own if something changed it
  /// elsewhere (e.g. starting a mode from the Modes tab). Ping this
  /// every time Today becomes the visible tab so it refreshes instead
  /// of silently showing what it looked like when it was last built.
  final _todayRefresh = ValueNotifier<int>(0);

  @override
  void dispose() {
    _todayRefresh.dispose();
    super.dispose();
  }

  void _onDestinationSelected(int index) {
    setState(() => _index = index);
    if (index == 0) _todayRefresh.value++;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _DemoBanner(),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: [
                  TodayScreen(
                    store: widget.store,
                    syncService: widget.syncService,
                    readoutService: widget.readoutService,
                    modeService: widget.modeService,
                    refreshSignal: _todayRefresh,
                  ),
                  TrendsScreen(store: widget.store),
                  StoryScreen(storyService: widget.storyService),
                  ModesScreen(modeService: widget.modeService),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(
              icon: Icon(Icons.show_chart), label: 'Trends'),
          NavigationDestination(icon: Icon(Icons.menu_book), label: 'Story'),
          NavigationDestination(icon: Icon(Icons.flag), label: 'Modes'),
        ],
      ),
    );
  }
}

/// Unmissable — screenshots of this build must never be mistaken for
/// real ring data, on any tab.
class _DemoBanner extends StatelessWidget {
  const _DemoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.amber,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: const Text(
        'DEMO — simulated ring data',
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
      ),
    );
  }
}
