/// Sync service tests: the full pipeline, mock ring -> sync -> SQLite.
/// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hux_app/core/ring/mock_ring_adapter.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:hux_app/core/sync/sync_service.dart';

void main() {
  sqfliteFfiInit();

  Future<SqliteHealthStore> openStore() =>
      SqliteHealthStore.open(inMemoryDatabasePath,
          factory: databaseFactoryFfi);

  test('first sync pulls the first-sync window and sets the watermark',
      () async {
    final ring = MockRingAdapter(seed: 3);
    final store = await openStore();
    final sync = SyncService(ring, store,
        firstSyncWindow: const Duration(days: 2),
        maxAttempts: 5,
        baseBackoff: const Duration(milliseconds: 10));

    final outcome = await sync.syncNow();

    expect(outcome.success, isTrue, reason: outcome.error ?? '');
    expect(outcome.snapshotsSaved, greaterThan(200)); // ~2 days of data
    expect(outcome.sleepSessionsSaved, greaterThanOrEqualTo(1));
    expect(await store.lastSyncedUpTo(), isNotNull);

    await sync.dispose();
    await ring.dispose();
    await store.close();
  });

  test('second sync with overlap does not duplicate data', () async {
    final ring = MockRingAdapter(seed: 3);
    final store = await openStore();
    final sync = SyncService(ring, store,
        firstSyncWindow: const Duration(hours: 12),
        overlap: const Duration(hours: 2),
        maxAttempts: 5,
        baseBackoff: const Duration(milliseconds: 10));

    await sync.syncNow();
    final afterFirst = await store.snapshotsBetween(
        DateTime.utc(2000), DateTime.now().toUtc());

    // Immediately sync again: everything fetched is inside the overlap.
    final second = await sync.syncNow();
    expect(second.success, isTrue);

    final afterSecond = await store.snapshotsBetween(
        DateTime.utc(2000), DateTime.now().toUtc());

    // Idempotent store: overlap re-fetch must not inflate the count
    // (a few NEW minutes may have passed, so allow a tiny delta).
    expect(afterSecond.length - afterFirst.length, lessThanOrEqualTo(2),
        reason: 'overlap must be deduplicated by the store');

    await sync.dispose();
    await ring.dispose();
    await store.close();
  });

  test('sync survives flaky connections via retry', () async {
    // Chaos mode ring + generous retries: sync should still succeed
    // far more often than raw connect() does.
    final ring = MockRingAdapter(seed: 11, chaosMode: true);
    final store = await openStore();
    final sync = SyncService(ring, store,
        firstSyncWindow: const Duration(hours: 6),
        maxAttempts: 6,
        baseBackoff: const Duration(milliseconds: 5));

    final outcome = await sync.syncNow();
    expect(outcome.success, isTrue, reason: outcome.error ?? '');

    await sync.dispose();
    await ring.dispose();
    await store.close();
  });

  test('re-entrant syncNow is rejected, not raced', () async {
    final ring = MockRingAdapter(seed: 5);
    final store = await openStore();
    final sync = SyncService(ring, store,
        firstSyncWindow: const Duration(days: 3),
        baseBackoff: const Duration(milliseconds: 10));

    final first = sync.syncNow(); // don't await yet
    final second = await sync.syncNow(); // while first is running

    expect(second.success, isFalse);
    expect(second.error, contains('in progress'));
    expect((await first).success, isTrue);

    await sync.dispose();
    await ring.dispose();
    await store.close();
  });
}
