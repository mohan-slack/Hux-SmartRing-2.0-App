/// The app's top-level shell: bottom navigation across Today, Trends,
/// and Story. The demo banner is pinned here, above all three tabs —
/// a single, unmissable element rather than three copies that could
/// drift out of sync. Each tab keeps its own state when you switch
/// away and back (IndexedStack builds every tab once and keeps them
/// alive, rather than disposing and rebuilding on every switch).

import 'package:flutter/material.dart';

import '../core/meaning/readout_service.dart';
import '../core/meaning/weekly_story.dart';
import '../core/storage/health_store.dart';
import '../core/sync/sync_service.dart';
import 'story_screen.dart';
import 'today_screen.dart';
import 'trends_screen.dart';

class AppShell extends StatefulWidget {
  final HealthStore store;
  final SyncService syncService;
  final ReadoutService readoutService;
  final WeeklyStoryService storyService;

  const AppShell({
    super.key,
    required this.store,
    required this.syncService,
    required this.readoutService,
    required this.storyService,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

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
                  ),
                  TrendsScreen(store: widget.store),
                  StoryScreen(storyService: widget.storyService),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(
              icon: Icon(Icons.show_chart), label: 'Trends'),
          NavigationDestination(icon: Icon(Icons.menu_book), label: 'Story'),
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
