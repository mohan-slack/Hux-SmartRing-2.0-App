/// Tests for [ReadoutService], focused on the staleness guard: a session
/// synced days ago must never be presented as "last night".
/// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hux_app/core/meaning/daily_readout.dart';
import 'package:hux_app/core/meaning/readout_service.dart';
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
}
