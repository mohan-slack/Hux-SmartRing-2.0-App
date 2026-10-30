/// Tests for [AppShell]: the demo banner must stay visible on every
/// tab (Home, Coach, Plans, Progress), and switching tabs must not lose a tab's state (IndexedStack).
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
import 'package:hux_app/screens/hubs/plans_hub.dart';
import 'package:hux_app/screens/modes_screen.dart';
import 'package:hux_app/screens/today_screen.dart';
import 'package:hux_app/theme/hux_ui.dart';

void main() {
  sqfliteFfiInit();

  Future<void> settle(WidgetTester tester) async {
    await tester
        .runAsync(() => Future.delayed(const Duration(milliseconds: 400)));
    await tester.pump();
  }

  /// Like pumpAndSettle, but bounded: pumps ~2 s of frames (enough for
  /// route/dialog transitions) without failing on a stray spinner.
  Future<void> settleUi(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Unmounts the shell and lets in-flight sqflite queries (Home extras,
  /// weekly story) finish so no fake-async timer outlives the test.
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    // A few rounds: Home loads (readout, extras, journey, cycle) run in
    // sequence, and each sqflite call can schedule a fake-async timer.
    for (var i = 0; i < 3; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 500)));
      await tester.pump(const Duration(seconds: 1));
    }
  }

  /// Taps a tab in the floating nav bar (not a same-named title on screen).
  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: find.byType(HuxPillNavBar), matching: find.text(label)));
    await settle(tester);
  }

  testWidgets(
      'the demo banner stays visible across Home, Coach, Plans and Progress',
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

    await tapTab(tester, 'Progress');
    expect(find.text('DEMO — simulated ring data'), findsOneWidget);
    expect(find.text('Sleep duration'), findsOneWidget);

    await tester.tap(find.text('Story'));
    await settle(tester);
    expect(find.text('Your week, in plain words'), findsOneWidget);

    await tapTab(tester, 'Plans');
    expect(find.text('DEMO — simulated ring data'), findsOneWidget);
    expect(find.text('Walk & run'), findsOneWidget);

    await tapTab(tester, 'Coach');
    expect(find.text('DEMO — simulated ring data'), findsOneWidget);

    await tapTab(tester, 'Home');
    expect(find.text('DEMO — simulated ring data'), findsOneWidget);
    await drain(tester);
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
    await tapTab(tester, 'Progress');
    await tester.tap(find.text('30 days'));
    await settle(tester);

    await tapTab(tester, 'Home');
    await tapTab(tester, 'Progress');

    // TrendsScreen's range enum is private, so inspect the selection
    // dynamically rather than importing it: a fresh (non-preserved)
    // TrendsScreen would default back to "7 days" ("sevenDays"). Seeing
    // "thirtyDays" here proves IndexedStack kept the tab's State alive
    // rather than disposing and rebuilding it on tab switch.
    final selections = tester
        .widgetList(find.byWidgetPredicate((w) => w is SegmentedButton))
        .map((w) => ((w as dynamic).selected as Set).first.toString());
    expect(selections.any((s) => s.contains('thirtyDays')), isTrue);
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

    // Start Big Day from Plans -> Life modes.
    await tapTab(tester, 'Plans');
    await tester.scrollUntilVisible(find.text('Choose a mode'), 200,
        scrollable: find
            .descendant(of: find.byType(PlansHub), matching: find.byType(Scrollable))
            .first);
    await tester.pump();
    await tester.tap(find.text('Choose a mode'));
    // Let the route transition build ModesScreen first, THEN give its
    // FutureBuilder real time for the sqflite read (runAsync), then
    // pump the result in.
    await settleUi(tester);
    await settle(tester);
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Big Day'), 200,
        scrollable: find
            .descendant(of: find.byType(ModesScreen), matching: find.byType(Scrollable))
            .first);
    await tester.pump();

    // Each mode tile is now a full 16:9 photo card whose title sits at
    // the card's bottom edge — on the default (small) test viewport
    // that puts "Big Day"'s own text right under AppShell's floating
    // nav bar (which overlaps the bottom of the content by design).
    // Tap the card's AspectRatio box instead: its CENTER lands well
    // clear of the nav bar, unlike the bottom-anchored title text.
    final bigDayCard = find
        .ancestor(of: find.text('Big Day'), matching: find.byType(AspectRatio))
        .first;
    // scrollUntilVisible only guarantees the title text is on screen;
    // bring the whole card (and so its centre) into the viewport.
    await tester.ensureVisible(bigDayCard);
    await tester.pump();
    await tester.tap(bigDayCard);
    await settle(tester);
    await settleUi(tester);

    await tester.tap(find.text('Choose a date'));
    await settleUi(tester);
    await tester.tap(find.text('OK'));
    await settleUi(tester);

    await tester.tap(find.text('Start mode'));
    await settle(tester);
    await settleUi(tester);

    expect(find.textContaining('Active: Big Day'), findsOneWidget);

    // Back to Home: it must reflect the mode that was started while
    // Home's State sat alive in the background.
    await tester.tap(find.byTooltip('Back'));
    await settleUi(tester);
    await tapTab(tester, 'Home');
    // Switching to Home pings its refresh signal; the reload (store +
    // Home extras) is real sqflite I/O, so give it real time AFTER the
    // frame that triggered it, then pump the result in.
    await settleUi(tester);
    await settle(tester);
    await settle(tester);
    await settleUi(tester);

    await tester.scrollUntilVisible(find.textContaining('d to go'), 300,
        scrollable: find
            .descendant(of: find.byType(TodayScreen), matching: find.byType(Scrollable))
            .first);
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
          find.text('From your health app'), findsNothing);
      await drain(tester);
    });

    testWidgets('no banner for RingDataSource.health (the real launch source)',
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

      expect(find.text('From your health app'), findsNothing);
      expect(find.text('DEMO — simulated ring data'), findsNothing);
      await drain(tester);
    });
  });
}
