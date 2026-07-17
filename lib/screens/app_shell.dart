/// The app's top-level shell: bottom navigation across Today, Trends,
/// Story, and Modes. The demo banner is pinned here, above all four
/// tabs — a single, unmissable element rather than four copies that
/// could drift out of sync. Each tab keeps its own state when you
/// switch away and back (IndexedStack builds every tab once and keeps
/// them alive, rather than disposing and rebuilding on every switch).
///
/// Liquid-glass notes: the dark stage ([HuxBackground]) is painted
/// ONCE here behind everything; screens never paint their own. The nav
/// bar is the app's ONE real BackdropFilter — `extendBody: true` lets
/// tab content scroll behind it, so the blur has something genuine to
/// refract (see hux_glass.dart for why panels elsewhere fake it).

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/meaning/readout_service.dart';
import '../core/meaning/weekly_story.dart';
import '../core/modes/mode_service.dart';
import '../core/ring/data_source.dart';
import '../core/storage/health_store.dart';
import '../core/sync/sync_service.dart';
import '../theme/hux_glass.dart';
import '../theme/hux_tokens.dart';
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

  /// Which [RingAdapter] the composition root wired up — decides the
  /// banner's text and color. Defaults to [RingDataSource.mock] so
  /// every existing caller/test that predates this field is unaffected.
  final RingDataSource dataSource;

  const AppShell({
    super.key,
    required this.store,
    required this.syncService,
    required this.readoutService,
    required this.storyService,
    required this.modeService,
    this.dataSource = RingDataSource.mock,
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
      // Content scrolls behind the glass nav bar; each tab's scrollable
      // adds HuxGlass.navClearance of bottom padding so its last card
      // can still scroll fully clear of the bar.
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const HuxBackground(),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _SourceBanner(source: widget.dataSource),
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
        ],
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: HuxGlass.navBlurSigma,
            sigmaY: HuxGlass.navBlurSigma,
          ),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _onDestinationSelected,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.today), label: 'Today'),
              NavigationDestination(
                  icon: Icon(Icons.show_chart), label: 'Trends'),
              NavigationDestination(
                  icon: Icon(Icons.menu_book), label: 'Story'),
              NavigationDestination(icon: Icon(Icons.flag), label: 'Modes'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Unmissable — screenshots of this build must never be mistaken for
/// real ring data, on any tab. Text and color both follow [source]
/// truthfully: mock stays the original amber "DEMO" banner; the
/// health-store dev adapter gets a visually distinct blue-grey "DEV"
/// banner so the two are never confused for each other either.
class _SourceBanner extends StatelessWidget {
  final RingDataSource source;

  const _SourceBanner({required this.source});

  Color get _background => switch (source) {
        RingDataSource.mock => HuxColors.demoAmber,
        RingDataSource.health => HuxColors.devBlueGrey,
      };

  // Amber is light — the dedicated on-accent ink keeps ~10:1 contrast
  // (the app's regular ink is near-white now and would vanish on it).
  // Blue-grey is dark enough (see hux_tokens.dart) that white text
  // clears the 4.5:1 floor at ~7.2:1.
  Color get _foreground => switch (source) {
        RingDataSource.mock => HuxColors.inkOnAccent,
        RingDataSource.health => Colors.white,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _background,
      padding: const EdgeInsets.symmetric(
          vertical: HuxSpacing.sm, horizontal: HuxSpacing.lg),
      child: Text(
        source.bannerText,
        textAlign: TextAlign.center,
        style: TextStyle(fontWeight: FontWeight.bold, color: _foreground),
      ),
    );
  }
}
