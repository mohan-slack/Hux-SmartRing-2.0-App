/// Shared-phone privacy guard: another account's data is wiped on
/// sign-in; the same account keeps its data. Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/auth/local_data_guard.dart';
import 'package:hux_app/core/ring/ring_models.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  Future<SqliteHealthStore> openStore() =>
      SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);

  Future<void> seed(SqliteHealthStore store) async {
    await store.saveSnapshots([
      HealthSnapshot(timestamp: DateTime.utc(2026, 7, 1, 8), heartRateBpm: 60),
    ]);
    await store.setLastSyncedUpTo(DateTime.utc(2026, 7, 1, 9));
  }

  test('first sign-in on a device claims the data without wiping it', () async {
    final store = await openStore();
    await seed(store);

    await ensureLocalDataBelongsTo(store, 'user-a');

    expect(await store.dataOwnerId(), 'user-a');
    expect(await store.latestSnapshot(), isNotNull);
    await store.close();
  });

  test('the same account signing back in keeps its data', () async {
    final store = await openStore();
    await ensureLocalDataBelongsTo(store, 'user-a');
    await seed(store);

    await ensureLocalDataBelongsTo(store, 'user-a');

    expect(await store.latestSnapshot(), isNotNull);
    expect(await store.lastSyncedUpTo(), isNotNull);
    await store.close();
  });

  test('a different account wipes the previous account\'s data first', () async {
    final store = await openStore();
    await ensureLocalDataBelongsTo(store, 'user-a');
    await seed(store);

    await ensureLocalDataBelongsTo(store, 'user-b');

    expect(await store.latestSnapshot(), isNull);
    expect(await store.lastSyncedUpTo(), isNull,
        reason: 'watermark cleared, so user B gets a fresh first sync');
    expect(await store.dataOwnerId(), 'user-b');
    await store.close();
  });
}
