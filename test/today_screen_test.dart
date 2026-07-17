/// Widget tests for [TodayScreen]. Run with: flutter test
///
/// `testWidgets` runs its body in a zone where real `Timer`s never fire
/// on their own — only `tester.pump()` advances them. That bites twice
/// here: `MockRingAdapter` uses `Future.delayed` to simulate BLE
/// latency, and sqflite's own lock handling is timer-based internally.
/// Any real async work — pre-seeding data, and letting the screen's own
/// initState-triggered DB reads actually complete — has to run inside
/// `tester.runAsync()`, which steps outside that zone; `pumpAndSettle()`
/// alone hangs waiting on both.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hux_app/core/meaning/daily_readout.dart';
import 'package:hux_app/core/meaning/readout_service.dart';
import 'package:hux_app/core/modes/content/event_content.dart';
import 'package:hux_app/core/modes/mode.dart';
import 'package:hux_app/core/modes/mode_service.dart';
import 'package:hux_app/core/ring/mock_ring_adapter.dart';
import 'package:hux_app/core/ring/ring_models.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:hux_app/core/sync/sync_service.dart';
import 'package:hux_app/screens/today_screen.dart';

void main() {
  sqfliteFfiInit();

  Future<SqliteHealthStore> openStore() =>
      SqliteHealthStore.open(inMemoryDatabasePath,
          factory: databaseFactoryFfi);

  /// Lets the screen's own real async work (DB reads kicked off from
  /// initState) actually finish, then rebuilds. Not `pumpAndSettle()`:
  /// the loading spinner animates forever, so it would just time out.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
  }

  testWidgets(
      'renders headline and actions once already synced',
      (tester) async {
    late SqliteHealthStore store;
    late MockRingAdapter ring;
    late SyncService syncService;
    late ReadoutService readoutService;
    late DailyReadout expectedReadout;

    // Pre-seed via the real mock-ring -> sync pipeline, exactly like a
    // device that's already synced before — the screen should not try
    // to sync again on open. Runs for real (not the fake test clock)
    // since MockRingAdapter's simulated BLE delays are real timers.
    await tester.runAsync(() async {
      store = await openStore();
      ring = MockRingAdapter(seed: 7);
      syncService = SyncService(
        ring,
        store,
        firstSyncWindow: const Duration(days: 10),
        maxAttempts: 5,
        baseBackoff: const Duration(milliseconds: 10),
      );
      readoutService = ReadoutService(store);

      final outcome = await syncService.syncNow();
      expect(outcome.success, isTrue, reason: outcome.error ?? '');
      expectedReadout = await readoutService.today();
    });
    addTearDown(() async {
      await syncService.dispose();
      await ring.dispose();
      await store.close();
    });

    await tester.pumpWidget(MaterialApp(
      home: TodayScreen(
        store: store,
        syncService: syncService,
        readoutService: readoutService,
        modeService: ModeService(store),
      ),
    ));
    await settle(tester);

    expect(find.text(expectedReadout.headline), findsOneWidget);
    for (final action in expectedReadout.actions) {
      expect(find.text(action), findsOneWidget);
    }
  });

  testWidgets(
      'shows the still-learning state on a fresh store, without crashing',
      (tester) async {
    late SqliteHealthStore store;
    late MockRingAdapter ring;
    late SyncService syncService;
    late ReadoutService readoutService;

    // Fewer than 3 nights of history and an explicit watermark: the
    // baseline is insufficient, and the screen must not try to
    // auto-sync (it already has a watermark) — it should just render
    // the honest "still learning" readout.
    await tester.runAsync(() async {
      store = await openStore();
      ring = MockRingAdapter(seed: 9);
      syncService = SyncService(ring, store);
      readoutService = ReadoutService(store);

      final bedtime = DateTime.utc(2026, 7, 15, 23);
      await store.saveSleepSessions([
        SleepSession(
          bedtime: bedtime,
          wakeTime: bedtime.add(const Duration(hours: 7)),
          segments: [
            SleepSegment(
                start: bedtime,
                end: bedtime.add(const Duration(hours: 7)),
                stage: SleepStage.light),
          ],
          avgHeartRateBpm: 60,
          avgHrvMs: 50,
          avgSkinTempCelsius: 33.6,
        ),
      ]);
      await store.setLastSyncedUpTo(bedtime.add(const Duration(hours: 7)));
    });
    addTearDown(() async {
      await syncService.dispose();
      await ring.dispose();
      await store.close();
    });

    await tester.pumpWidget(MaterialApp(
      home: TodayScreen(
        store: store,
        syncService: syncService,
        readoutService: readoutService,
        modeService: ModeService(store),
      ),
    ));
    await settle(tester);

    expect(find.textContaining('learning your body'), findsOneWidget);
  });

  testWidgets('shows the ModeStrip card when an event mode is active',
      (tester) async {
    late SqliteHealthStore store;
    late MockRingAdapter ring;
    late SyncService syncService;
    late ReadoutService readoutService;
    late ModeService modeService;
    late String expectedAction;

    await tester.runAsync(() async {
      store = await openStore();
      ring = MockRingAdapter(seed: 21);
      syncService = SyncService(
        ring,
        store,
        firstSyncWindow: const Duration(days: 10),
        maxAttempts: 5,
        baseBackoff: const Duration(milliseconds: 10),
      );
      readoutService = ReadoutService(store);
      modeService = ModeService(store);

      final outcome = await syncService.syncNow();
      expect(outcome.success, isTrue, reason: outcome.error ?? '');

      // 10 days out lands squarely in the "Build" phase (8-21 days).
      final now = DateTime.now();
      await modeService.startMode(EventModeConfig(
        id: ModeId.shaadi,
        targetDate: now.add(const Duration(days: 10)),
        label: 'Test wedding',
        startedAt: now,
      ));
      expectedAction =
          EventContent.pickPhaseAction(ModeId.shaadi, EventPhase.build, now);
    });
    addTearDown(() async {
      await syncService.dispose();
      await ring.dispose();
      await store.close();
    });

    await tester.pumpWidget(MaterialApp(
      home: TodayScreen(
        store: store,
        syncService: syncService,
        readoutService: readoutService,
        modeService: modeService,
      ),
    ));
    await settle(tester);

    // The ModeStrip card sits below the fold on the default test
    // surface — a plain ListView only builds elements for what's near
    // the viewport, so scroll it into view rather than guessing a
    // taller surface size (which just moves the same problem to
    // whatever content is now off to the side).
    await tester.scrollUntilVisible(find.text('Build'), 300);
    await tester.pump();

    expect(find.text('Build'), findsOneWidget);
    expect(find.text('10d to go'), findsOneWidget);
    expect(find.text(expectedAction), findsOneWidget);
  });

  testWidgets(
      'shows a lifestyle context chip and "Last sleep" wording when '
      'Night Shift is active', (tester) async {
    late SqliteHealthStore store;
    late MockRingAdapter ring;
    late SyncService syncService;
    late ReadoutService readoutService;
    late ModeService modeService;

    await tester.runAsync(() async {
      store = await openStore();
      ring = MockRingAdapter(seed: 33);
      syncService = SyncService(
        ring,
        store,
        firstSyncWindow: const Duration(days: 10),
        maxAttempts: 5,
        baseBackoff: const Duration(milliseconds: 10),
      );
      modeService = ModeService(store);
      readoutService = ReadoutService(store, modeService: modeService);

      final outcome = await syncService.syncNow();
      expect(outcome.success, isTrue, reason: outcome.error ?? '');

      await modeService.startNightShift(NightShiftConfig(
        usualSleepStartHour: 9,
        usualSleepEndHour: 16,
        startedAt: DateTime.now(),
      ));
    });
    addTearDown(() async {
      await syncService.dispose();
      await ring.dispose();
      await store.close();
    });

    // Scaffold, not a bare MaterialApp(home:) — same as how AppShell
    // actually mounts TodayScreen. The chip is a Material `Chip`, which
    // (unlike everything else on this screen so far) asserts a Material
    // ancestor exists; the other tests in this file never exercised
    // that requirement.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TodayScreen(
          store: store,
          syncService: syncService,
          readoutService: readoutService,
          modeService: modeService,
        ),
      ),
    ));
    await settle(tester);

    expect(find.text('Night shift'), findsOneWidget);
    expect(find.text('Last sleep'), findsOneWidget);
    expect(find.text('Last night'), findsNothing);
  });
}
