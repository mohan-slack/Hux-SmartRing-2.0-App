/// Tests for [ReadoutService], focused on the staleness guard: a session
/// synced days ago must never be presented as "last night".
/// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hux_app/core/meaning/daily_readout.dart';
import 'package:hux_app/core/meaning/readout_service.dart';
import 'package:hux_app/core/modes/mode.dart';
import 'package:hux_app/core/modes/mode_service.dart';
import 'package:hux_app/core/ring/ring_models.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';

void main() {
  sqfliteFfiInit();

  Future<SqliteHealthStore> openStore() =>
      SqliteHealthStore.open(inMemoryDatabasePath,
          factory: databaseFactoryFfi);

  SleepSession fullNightAt(DateTime bedtime) {
    final wake = bedtime.add(const Duration(hours: 7));
    return SleepSession(
      bedtime: bedtime,
      wakeTime: wake,
      segments: [
        SleepSegment(start: bedtime, end: wake, stage: SleepStage.light),
      ],
      avgHeartRateBpm: 60,
      avgHrvMs: 50,
      avgSkinTempCelsius: 33.6,
    );
  }

  group('Staleness guard', () {
    test('a 3-day-old session is never presented as last night', () async {
      final store = await openStore();
      final now = DateTime.utc(2026, 7, 20, 9, 0);

      // 3 nights of real history (baseline is sufficient), but the most
      // recent one woke up ~66h ago — well past the 36h staleness cutoff.
      await store.saveSleepSessions([
        fullNightAt(now.subtract(const Duration(days: 5, hours: 1))),
        fullNightAt(now.subtract(const Duration(days: 4, hours: 1))),
        fullNightAt(now.subtract(const Duration(days: 3, hours: 1))),
      ]);

      final readout = await ReadoutService(store).today(now: now);

      // Must fall through to the "no usable data last night" readout,
      // not treat the stale night as fresh — proves the session was
      // excluded, not just coincidentally short on baseline history.
      expect(readout.headline, 'No readings from last night');
      expect(readout.state, RecoveryState.learning);
      expect(readout.dataQuality, DataQuality.sparse);

      await store.close();
    });

    test('a session within the staleness window is used normally',
        () async {
      final store = await openStore();
      final now = DateTime.utc(2026, 7, 20, 9, 0);

      await store.saveSleepSessions([
        fullNightAt(now.subtract(const Duration(days: 12))),
        fullNightAt(now.subtract(const Duration(days: 2))),
        // Woke up 10h ago: comfortably inside the 36h window.
        fullNightAt(now.subtract(const Duration(hours: 17))),
      ]);

      final readout = await ReadoutService(store).today(now: now);

      expect(readout.headline, isNot('No readings from last night'));
      expect(readout.dataQuality, DataQuality.full);

      await store.close();
    });
  });

  group('Lifestyle mode integration', () {
    Future<void> seedHistory(SqliteHealthStore store, DateTime now) async {
      // A handful of identical nights spread across the baseline window,
      // each at 23:00 UTC on its own calendar day — enough for the
      // baseline to be sufficient (>=3 nights of history).
      for (final daysAgo in [2, 5, 8, 11]) {
        final day = now.subtract(Duration(days: daysAgo));
        await store.saveSleepSessions(
            [fullNightAt(DateTime.utc(day.year, day.month, day.day, 23))]);
      }
      // A fresh, well-inside-the-staleness-window night for "last night".
      await store.saveSleepSessions(
          [fullNightAt(now.subtract(const Duration(hours: 17)))]);
    }

    test('without a ModeService, behaves exactly as before (no crash, '
        'ordinary wording)', () async {
      final store = await openStore();
      final now = DateTime.utc(2026, 7, 20, 9, 0);
      await seedHistory(store, now);

      final readout = await ReadoutService(store).today(now: now);
      expect(readout.meaning.toLowerCase(), isNot(contains('last sleep')));

      await store.close();
    });

    test('with Night Shift active, the readout uses "last sleep" wording',
        () async {
      final store = await openStore();
      final now = DateTime.utc(2026, 7, 20, 9, 0);
      await seedHistory(store, now);

      final modeService = ModeService(store);
      await modeService.startNightShift(NightShiftConfig(
        usualSleepStartHour: 9,
        usualSleepEndHour: 16,
        startedAt: now,
      ));

      final readout =
          await ReadoutService(store, modeService: modeService).today(now: now);

      expect(readout.meaning.toLowerCase(), isNot(contains('last night')));
      expect(readout.meaning.toLowerCase(), contains('sleep'));

      await store.close();
    });

    test('with Fasting Companion active today, no daytime-food action '
        'appears and a fasting-specific action is layered in', () async {
      final store = await openStore();
      final now = DateTime.utc(2026, 3, 5, 9, 0);
      await seedHistory(store, now);

      final modeService = ModeService(store);
      await modeService.startFasting(FastingConfig(
        type: FastType.roza,
        start: DateTime.utc(2026, 3, 1),
        end: DateTime.utc(2026, 3, 30),
        startedAt: DateTime.utc(2026, 2, 28),
      ));

      final readout =
          await ReadoutService(store, modeService: modeService).today(now: now);

      expect(
        readout.actions.any((a) => a.toLowerCase().contains('chai') ||
            a.toLowerCase().contains('thali') ||
            a.toLowerCase().contains('lemon to your water')),
        isFalse,
        reason: 'no daytime-food action should appear on a fast day: '
            '${readout.actions}',
      );
      expect(
        readout.actions.any((a) => a.contains('Roza')),
        isTrue,
        reason: 'a fasting-specific action should be layered in: '
            '${readout.actions}',
      );

      await store.close();
    });

    test('Fasting Companion configured but NOT active today leaves the '
        'readout untouched', () async {
      final store = await openStore();
      final now = DateTime.utc(2026, 4, 15, 9, 0); // well after the fast ends
      await seedHistory(store, now);

      final modeService = ModeService(store);
      await modeService.startFasting(FastingConfig(
        type: FastType.roza,
        start: DateTime.utc(2026, 3, 1),
        end: DateTime.utc(2026, 3, 30),
        startedAt: DateTime.utc(2026, 2, 28),
      ));

      final readout =
          await ReadoutService(store, modeService: modeService).today(now: now);

      expect(readout.actions.any((a) => a.contains('Roza')), isFalse);

      await store.close();
    });
  });
}
