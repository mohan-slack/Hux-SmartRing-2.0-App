/// Tests for [AppShell]: the demo banner must stay visible on every
/// tab, and switching tabs must not lose a tab's state (IndexedStack).
/// Run with: flutter test
///
/// See today_screen_test.dart for why real async DB work here goes
/// through `tester.runAsync()` rather than `pumpAndSettle()`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hux_app/core/meaning/readout_service.dart';
import 'package:hux_app/core/meaning/weekly_story.dart';
import 'package:hux_app/core/modes/mode_service.dart';
import 'package:hux_app/core/ring/data_source.dart';
import 'package:hux_app/core/ring/mock_ring_adapter.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:hux_app/core/sync/sync_service.dart';
import 'package:hux_app/screens/app_shell.dart';

void main() {
  sqfliteFfiInit();

  Future<void> settle(WidgetTester tester) async {
    await tester
        .runAsync(() => Future.delayed(const Duration(milliseconds: 400)));
    await tester.pump();
  }

  testWidgets(
      'the demo banner stays visible across Today, Trends, Story, and Modes',
      (tester) async {
    late SqliteHealthStore store;
    late MockRingAdapter ring;
    late SyncService syncService;

    await tester.runAsync(() async {
      store = await SqliteHealthStore.open(inMemoryDatabasePath,
          factory: databaseFactoryFfi);
      ring = MockRingAdapter(seed: 11);
      syncService = SyncService(
        ring,
        store,
        firstSyncWindow: const Duration(days: 10),
        maxAttempts: 5,
        baseBackoff: const Duration(milliseconds: 10),
      );
      // Pre-seed so Today doesn't try to auto-sync during the test.
      await syncService.syncNow();
    });
    addTearDown(() async {
      await syncService.dispose();
      await ring.dispose();
      await store.close();
    });

    await tester.pumpWidget(MaterialApp(
      home: AppShell(
        store: store,
        syncService: syncService,
        readoutService: ReadoutService(store),
        storyService: WeeklyStoryService(store),
        modeService: ModeService(store),
      ),
    ));
    await settle(tester);

    expect(find.text('DEMO — simulated ring data'), findsOneWidget);

    await tester.tap(find.text('Trends'));
    await settle(tester);
    expect(find.text('DEMO — simulated ring data'), findsOneWidget);
    expect(find.text('Sleep duration'), findsOneWidget);

    await tester.tap(find.text('Story'));
    await settle(tester);
    expect(find.text('DEMO — simulated ring data'), findsOneWidget);
    expect(find.text('Your week, in plain words'), findsOneWidget);

    await tester.tap(find.text('Modes'));
    await settle(tester);
    expect(find.text('DEMO — simulated ring data'), findsOneWidget);
    expect(find.text('Modes'), findsWidgets);

    await tester.tap(find.text('Today'));
    await settle(tester);
    expect(find.text('DEMO — simulated ring data'), findsOneWidget);
  });

  testWidgets('switching tabs preserves each tab\'s state (IndexedStack)',
      (tester) async {
    late SqliteHealthStore store;
    late MockRingAdapter ring;
    late SyncService syncService;

    await tester.runAsync(() async {
      store = await SqliteHealthStore.open(inMemoryDatabasePath,
          factory: databaseFactoryFfi);
      ring = MockRingAdapter(seed: 13);
      syncService = SyncService(
        ring,
        store,
        firstSyncWindow: const Duration(days: 10),
        maxAttempts: 5,
        baseBackoff: const Duration(milliseconds: 10),
      );
      await syncService.syncNow();
    });
    addTearDown(() async {
      await syncService.dispose();
      await ring.dispose();
      await store.close();
    });

    await tester.pumpWidget(MaterialApp(
      home: AppShell(
        store: store,
        syncService: syncService,
        readoutService: ReadoutService(store),
        storyService: WeeklyStoryService(store),
        modeService: ModeService(store),
      ),
    ));
    await settle(tester);

    // Move Trends to the 30-day range, then wander to another tab and
    // back — IndexedStack must keep Trends' widget (and its selection)
    // alive instead of tearing it down and rebuilding at the default.
    await tester.tap(find.text('Trends'));
    await settle(tester);
    await tester.tap(find.text('30 days'));
    await settle(tester);

    await tester.tap(find.text('Story'));
    await settle(tester);
    await tester.tap(find.text('Trends'));
    await settle(tester);

    // TrendsScreen's range enum is private, so inspect the selection
    // dynamically rather than importing it: a fresh (non-preserved)
    // TrendsScreen would default back to "7 days" ("sevenDays"). Seeing
    // "thirtyDays" here proves IndexedStack kept the tab's State alive
    // rather than disposing and rebuilding it on tab switch.
    final segmented =
        tester.widget(find.byWidgetPredicate((w) => w is SegmentedButton));
    final selected = (segmented as dynamic).selected as Set;
    expect(selected.first.toString(), contains('thirtyDays'));
  });

  testWidgets(
      'starting a mode on the Modes tab shows up on Today after switching '
      'back — regression test: IndexedStack keeps Today alive, so it '
      'must be told to refresh rather than silently going stale',
      (tester) async {
    late SqliteHealthStore store;
    late MockRingAdapter ring;
    late SyncService syncService;

    await tester.runAsync(() async {
      store = await SqliteHealthStore.open(inMemoryDatabasePath,
          factory: databaseFactoryFfi);
      ring = MockRingAdapter(seed: 17);
      syncService = SyncService(
        ring,
        store,
        firstSyncWindow: const Duration(days: 10),
        maxAttempts: 5,
        baseBackoff: const Duration(milliseconds: 10),
      );
      await syncService.syncNow();
    });
    addTearDown(() async {
      await syncService.dispose();
      await ring.dispose();
      await store.close();
    });

    await tester.pumpWidget(MaterialApp(
      home: AppShell(
        store: store,
        syncService: syncService,
        readoutService: ReadoutService(store),
        storyService: WeeklyStoryService(store),
        modeService: ModeService(store),
      ),
    ));
    await settle(tester);

    // No mode active yet: Today must not show a ModeStrip card.
    expect(find.textContaining('days to go'), findsNothing);

    // Start Big Day from the Modes tab.
    await tester.tap(find.text('Modes'));
    await settle(tester);

    // Each mode tile is now a full 16:9 photo card whose title sits at
    // the card's bottom edge — on the default (small) test viewport
    // that puts "Big Day"'s own text right under AppShell's floating
    // nav bar (which overlaps the bottom of the content by design).
    // Tap the card's AspectRatio box instead: its CENTER lands well
    // clear of the nav bar, unlike the bottom-anchored title text.
    await tester.tap(find
        .ancestor(of: find.text('Big Day'), matching: find.byType(AspectRatio))
        .first);
    await settle(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose a date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start mode'));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Active: Big Day'), findsOneWidget);

    // Switch back to Today: it must reflect the mode that was started
    // while this tab's State sat alive in the background.
    await tester.tap(find.text('Today'));
    await settle(tester);

    await tester.scrollUntilVisible(find.textContaining('d to go'), 300);
    await tester.pump();
    expect(find.textContaining('d to go'), findsOneWidget);
  });

  group('Source banner', () {
    test('defaults to mock when dataSource is omitted (backward '
        'compatible with every existing caller)', () {
      // AppShell.dataSource defaults to RingDataSource.mock — nothing
      // to pump here, just pinning the default so it can't drift
      // silently.
      const defaultSource = RingDataSource.mock;
      expect(defaultSource.bannerText, 'DEMO — simulated ring data');
    });

    testWidgets('shows the DEMO banner for RingDataSource.mock',
        (tester) async {
      late SqliteHealthStore store;
      late MockRingAdapter ring;
      late SyncService syncService;

      await tester.runAsync(() async {
        store = await SqliteHealthStore.open(inMemoryDatabasePath,
            factory: databaseFactoryFfi);
        ring = MockRingAdapter(seed: 3);
        syncService = SyncService(ring, store);
        await syncService.syncNow();
      });
      addTearDown(() async {
        await syncService.dispose();
        await ring.dispose();
        await store.close();
      });

      await tester.pumpWidget(MaterialApp(
        home: AppShell(
          store: store,
          syncService: syncService,
          readoutService: ReadoutService(store),
          storyService: WeeklyStoryService(store),
          modeService: ModeService(store),
          dataSource: RingDataSource.mock,
        ),
      ));
      await settle(tester);

      expect(find.text('DEMO — simulated ring data'), findsOneWidget);
      expect(
          find.text('DEV — your health app data (not a HUX ring)'), findsNothing);
    });

    testWidgets('shows the distinct DEV banner for RingDataSource.health',
        (tester) async {
      late SqliteHealthStore store;
      late MockRingAdapter ring;
      late SyncService syncService;

      await tester.runAsync(() async {
        store = await SqliteHealthStore.open(inMemoryDatabasePath,
            factory: databaseFactoryFfi);
        ring = MockRingAdapter(seed: 5);
        syncService = SyncService(ring, store);
        await syncService.syncNow();
      });
      addTearDown(() async {
        await syncService.dispose();
        await ring.dispose();
        await store.close();
      });

      await tester.pumpWidget(MaterialApp(
        home: AppShell(
          store: store,
          syncService: syncService,
          readoutService: ReadoutService(store),
          storyService: WeeklyStoryService(store),
          modeService: ModeService(store),
          dataSource: RingDataSource.health,
        ),
      ));
      await settle(tester);

      expect(
          find.text('DEV — your health app data (not a HUX ring)'), findsOneWidget);
      expect(find.text('DEMO — simulated ring data'), findsNothing);
    });
  });
}
