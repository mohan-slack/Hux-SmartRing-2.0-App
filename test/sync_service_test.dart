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

  test('second sync with overlap never loses or duplicates a reading',
      () async {
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
    final firstTimestamps = afterFirst.map((s) => s.timestamp).toSet();

    // Immediately sync again: everything fetched is inside the overlap.
    final second = await sync.syncNow();
    expect(second.success, isTrue);

    final afterSecond = await store.snapshotsBetween(
        DateTime.utc(2000), DateTime.now().toUtc());
    final secondTimestamps = afterSecond.map((s) => s.timestamp).toSet();

    // The mock rolls its ~7% miss chance independently on every fetch, so
    // the overlap window can legitimately gain snapshots the ring dropped
    // the first time and filled in on the retry — that's the overlap
    // doing its job, not a bug. What idempotency actually guarantees:
    // nothing already synced is ever lost, and no timestamp is ever
    // stored more than once.
    expect(secondTimestamps.containsAll(firstTimestamps), isTrue,
        reason: 'overlap must never lose an already-synced reading');
    expect(afterSecond.length, secondTimestamps.length,
        reason: 'no timestamp should ever be stored more than once');

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
