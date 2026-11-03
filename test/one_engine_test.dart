/// One source of truth: the readout's state (and headline) follows the
/// morning Charge, so the words never contradict the number.
/// Run with: flutter test test/one_engine_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/meaning/daily_readout.dart';
import 'package:hux_app/core/meaning/hux_charge.dart';
import 'package:hux_app/core/meaning/meaning_engine.dart';
import 'package:hux_app/core/meaning/readout_service.dart';
import 'package:hux_app/core/ring/ring_models.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('charge cut-offs map to the four states', () {
    expect(MeaningEngine.stateForCharge(90), RecoveryState.recharged);
    expect(MeaningEngine.stateForCharge(HuxChargeCalculator.fullAt), RecoveryState.recharged);
    expect(MeaningEngine.stateForCharge(60), RecoveryState.steady);
    expect(MeaningEngine.stateForCharge(40), RecoveryState.stretched);
    expect(MeaningEngine.stateForCharge(10), RecoveryState.rundown);
  });

  test('a usual 5 h sleeper: engine alone says "normal", the readout follows Charge', () async {
    final store = await SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);
    final now = DateTime(2026, 11, 8, 9);
    await store.saveSleepSessions([
      for (var d = 1; d <= 8; d++)
        () {
          final wake = DateTime(2026, 11, d, 7);
          final bed = wake.subtract(const Duration(hours: 5));
          return SleepSession(
            bedtime: bed,
            wakeTime: wake,
            segments: [SleepSegment(start: bed, end: wake, stage: SleepStage.light)],
            avgHrvMs: 50,
            avgHeartRateBpm: 60,
          );
        }(),
    ]);
    final r = await ReadoutService(store).today(now: now);
    expect(r.charge?.level, ChargeLevel.low); // 5 h every night is not "Good to go"
    expect(r.state, RecoveryState.stretched); // …and the headline agrees
    await store.close();
  });
}
