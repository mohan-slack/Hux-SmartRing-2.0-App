/// Smoke tests for [TrendsScreen]. Run with: flutter test
///
/// Chart widgets themselves don't need deep testing (see
/// night_row_test.dart for the real logic) — just that the screen
/// builds, toggles range, and never crashes on real or absent data.
/// See today_screen_test.dart for why real async DB work here goes
/// through `tester.runAsync()` rather than `pumpAndSettle()`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hux_app/core/ring/ring_models.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:hux_app/screens/trends_screen.dart';

void main() {
  sqfliteFfiInit();

  Future<SqliteHealthStore> openStore() =>
      SqliteHealthStore.open(inMemoryDatabasePath,
          factory: databaseFactoryFfi);

  Future<void> settle(WidgetTester tester) async {
    await tester
        .runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
  }

  testWidgets('empty store shows the friendly placeholder, never crashes',
      (tester) async {
    late SqliteHealthStore store;
    await tester.runAsync(() async {
      store = await openStore();
    });
    addTearDown(() => store.close());

    await tester.pumpWidget(MaterialApp(home: TrendsScreen(store: store)));
    await settle(tester);

    expect(find.text('Not enough data to show trends yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a populated store renders charts and the range toggle works',
      (tester) async {
    late SqliteHealthStore store;
    await tester.runAsync(() async {
      store = await openStore();
      final now = DateTime.utc(2026, 7, 20, 8, 0);
      final sessions = <SleepSession>[];
      for (var i = 1; i <= 20; i++) {
        final bedtime = DateTime.utc(now.year, now.month, now.day, 23)
            .subtract(Duration(days: i));
        final wake = bedtime.add(const Duration(hours: 7));
        sessions.add(SleepSession(
          bedtime: bedtime,
          wakeTime: wake,
          segments: [
            SleepSegment(start: bedtime, end: wake, stage: SleepStage.light),
          ],
          avgHrvMs: 45 + (i % 5),
          avgHeartRateBpm: 60 - (i % 3),
        ));
      }
      await store.saveSleepSessions(sessions);
    });
    addTearDown(() => store.close());

    await tester.pumpWidget(MaterialApp(home: TrendsScreen(store: store)));
    await settle(tester);

    expect(find.text('Not enough data to show trends yet'), findsNothing);
    expect(find.text('Sleep duration'), findsOneWidget);
    expect(find.text('Avg HRV'), findsOneWidget);
    // The glass chart cards are taller (hero numeral above each chart),
    // so the third card sits below the fold on the default test surface
    // — scroll it into view rather than assuming it's built.
    await tester.scrollUntilVisible(find.text('Avg resting heart rate'), 200);
    await tester.pump();
    expect(find.text('Avg resting heart rate'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Toggle to 30 days and let the reload settle — should not crash.
    await tester.tap(find.text('30 days'));
    await settle(tester);

    // The list kept its scroll offset from the scroll above, so the
    // first card is now ABOVE the viewport — scroll back up (negative
    // delta) before asserting on it.
    await tester.scrollUntilVisible(find.text('Sleep duration'), -200);
    await tester.pump();
    expect(find.text('Sleep duration'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
