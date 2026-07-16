/// Integration test: the full pipeline end to end.
/// MockRingAdapter -> SyncService -> SQLite (sqflite_common_ffi) ->
/// ReadoutService -> a valid DailyReadout.
/// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hux_app/core/meaning/daily_readout.dart';
import 'package:hux_app/core/meaning/readout_service.dart';
import 'package:hux_app/core/ring/mock_ring_adapter.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:hux_app/core/sync/sync_service.dart';

void main() {
  sqfliteFfiInit();

  test(
      'mock ring -> sync -> sqlite -> readout service produces a valid '
      'readout', () async {
    final ring = MockRingAdapter(seed: 21);
    final store = await SqliteHealthStore.open(inMemoryDatabasePath,
        factory: databaseFactoryFfi);
    final sync = SyncService(
      ring,
      store,
      firstSyncWindow: const Duration(days: 10),
      maxAttempts: 5,
      baseBackoff: const Duration(milliseconds: 10),
    );

    final outcome = await sync.syncNow();
    expect(outcome.success, isTrue, reason: outcome.error ?? '');
    expect(outcome.sleepSessionsSaved, greaterThanOrEqualTo(3),
        reason: 'need at least 3 nights for the baseline to be sufficient');

    final readoutService = ReadoutService(store);
    final readout = await readoutService.today();

    expect(readout, isA<DailyReadout>());
    expect(readout.headline, isNotEmpty);
    expect(readout.headline.length, lessThanOrEqualTo(60));
    expect(readout.meaning, isNotEmpty);
    expect(readout.actions.length, lessThanOrEqualTo(2));
    // 10 real nights of ring data is enough history that the baseline
    // should be sufficient and last night's readings usable.
    expect(readout.state, isNot(RecoveryState.learning));
    expect(readout.actions, isNotEmpty);

    await sync.dispose();
    await ring.dispose();
    await store.close();
  });
}
