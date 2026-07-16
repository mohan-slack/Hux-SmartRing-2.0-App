/// Storage layer tests. Run with: flutter test
/// Uses sqflite_common_ffi so tests run on any desktop/CI machine
/// without an emulator.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hux_app/core/ring/ring_models.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';

void main() {
  sqfliteFfiInit();

  Future<SqliteHealthStore> openStore() =>
      SqliteHealthStore.open(inMemoryDatabasePath,
          factory: databaseFactoryFfi);

  HealthSnapshot snap(DateTime t, {int? hr}) =>
      HealthSnapshot(timestamp: t, heartRateBpm: hr ?? 60, hrvMs: 50);

  SleepSession night(DateTime bedtime, {int? avgHr}) => SleepSession(
        bedtime: bedtime,
        wakeTime: bedtime.add(const Duration(hours: 8)),
        segments: [
          SleepSegment(
              start: bedtime,
              end: bedtime.add(const Duration(minutes: 15)),
              stage: SleepStage.awake),
          SleepSegment(
              start: bedtime.add(const Duration(minutes: 15)),
              end: bedtime.add(const Duration(hours: 8)),
              stage: SleepStage.light),
        ],
        avgHeartRateBpm: avgHr ?? 58,
      );

  group('Snapshot idempotency — the core guarantee', () {
    test('saving the same reading twice stores it once', () async {
      final store = await openStore();
      final t = DateTime.utc(2026, 7, 15, 8, 0);

      await store.saveSnapshots([snap(t)]);
      await store.saveSnapshots([snap(t)]); // the overlap re-fetch

      final all = await store.snapshotsBetween(
          t.subtract(const Duration(hours: 1)),
          t.add(const Duration(hours: 1)));
      expect(all.length, 1);
      await store.close();
    });

    test('re-sent reading with new values replaces the old one',
        () async {
      final store = await openStore();
      final t = DateTime.utc(2026, 7, 15, 8, 0);

      await store.saveSnapshots([snap(t, hr: 60)]);
      await store.saveSnapshots([snap(t, hr: 64)]); // ring recomputed

      final all = await store.snapshotsBetween(
          t, t.add(const Duration(minutes: 1)));
      expect(all.single.heartRateBpm, 64,
          reason: 'the ring is the source of truth for its readings');
      await store.close();
    });
  });

  group('Range queries', () {
    test('between is [from, to) ordered oldest first', () async {
      final store = await openStore();
      final base = DateTime.utc(2026, 7, 15);
      await store.saveSnapshots([
        snap(base.add(const Duration(hours: 2))),
        snap(base.add(const Duration(hours: 1))),
        snap(base.add(const Duration(hours: 3))),
      ]);

      final result = await store.snapshotsBetween(
        base.add(const Duration(hours: 1)),
        base.add(const Duration(hours: 3)), // exclusive
      );
      expect(result.length, 2);
      expect(result.first.timestamp.isBefore(result.last.timestamp), isTrue);
      await store.close();
    });

    test('latestSnapshot returns null on empty store, newest otherwise',
        () async {
      final store = await openStore();
      expect(await store.latestSnapshot(), isNull);

      final base = DateTime.utc(2026, 7, 15);
      await store.saveSnapshots(
          [snap(base), snap(base.add(const Duration(hours: 5)))]);
      final latest = await store.latestSnapshot();
      expect(latest!.timestamp, base.add(const Duration(hours: 5)));
      await store.close();
    });
  });

  group('Sleep sessions', () {
    test('round-trip preserves segments in order', () async {
      final store = await openStore();
      final bedtime = DateTime.utc(2026, 7, 14, 23, 30);
      await store.saveSleepSessions([night(bedtime)]);

      final loaded = await store.latestSleepSession();
      expect(loaded!.bedtime, bedtime);
      expect(loaded.segments.length, 2);
      expect(loaded.segments.first.stage, SleepStage.awake);
      expect(loaded.segments.last.stage, SleepStage.light);
      await store.close();
    });

    test('re-saving the same night replaces it, not duplicates it',
        () async {
      final store = await openStore();
      final bedtime = DateTime.utc(2026, 7, 14, 23, 30);

      await store.saveSleepSessions([night(bedtime, avgHr: 58)]);
      await store.saveSleepSessions([night(bedtime, avgHr: 56)]);

      final sessions = await store.sleepSessionsBetween(
          bedtime.subtract(const Duration(days: 1)),
          bedtime.add(const Duration(days: 1)));
      expect(sessions.length, 1);
      expect(sessions.single.avgHeartRateBpm, 56);
      await store.close();
    });
  });

  group('Sync watermark', () {
    test('null before first sync, then persists what was set', () async {
      final store = await openStore();
      expect(await store.lastSyncedUpTo(), isNull);

      final mark = DateTime.utc(2026, 7, 15, 9, 0);
      await store.setLastSyncedUpTo(mark);
      expect(await store.lastSyncedUpTo(), mark);
      await store.close();
    });
  });

  group('Delete all data (DPDP)', () {
    test('wipes snapshots, sessions and watermark', () async {
      final store = await openStore();
      final t = DateTime.utc(2026, 7, 15, 8, 0);
      await store.saveSnapshots([snap(t)]);
      await store.saveSleepSessions([night(t)]);
      await store.setLastSyncedUpTo(t);

      await store.deleteAllData();

      expect(await store.latestSnapshot(), isNull);
      expect(await store.latestSleepSession(), isNull);
      expect(await store.lastSyncedUpTo(), isNull);
      await store.close();
    });
  });
}
