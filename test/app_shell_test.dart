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
      'the demo banner stays visible across Today, Trends, and Story',
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
}
