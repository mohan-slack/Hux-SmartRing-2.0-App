/// Storage layer tests. Run with: flutter test
/// Uses sqflite_common_ffi so tests run on any desktop/CI machine
/// without an emulator.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hux_app/core/modes/mode.dart';
import 'package:hux_app/core/ring/ring_models.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';

void main() {
  sqfliteFfiInit();

  Future<SqliteHealthStore> openStore() =>
      SqliteHealthStore.open(inMemoryDatabasePath,
          factory: databaseFactoryFfi);

  HealthSnapshot snap(DateTime t, {int? hr}) => HealthSnapshot(
        timestamp: t,
        heartRateBpm: hr ?? 60,
        hrvMs: 50,
        respiratoryRateBrpm: 15,
        activeEnergyKcal: 120,
        stressIndex: 42,
      );

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
        avgRespiratoryRateBrpm: 14,
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
      expect(all.single.respiratoryRateBrpm, 15);
      expect(all.single.activeEnergyKcal, 120);
      expect(all.single.stressIndex, 42);
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
      expect(loaded.avgRespiratoryRateBrpm, 14);
      await store.close();
    });

    test('a null avgRespiratoryRateBrpm round-trips as null, not zero',
        () async {
      final store = await openStore();
      final bedtime = DateTime.utc(2026, 7, 14, 23, 30);
      await store.saveSleepSessions([
        SleepSession(
          bedtime: bedtime,
          wakeTime: bedtime.add(const Duration(hours: 8)),
          segments: [
            SleepSegment(
                start: bedtime,
                end: bedtime.add(const Duration(hours: 8)),
                stage: SleepStage.light),
          ],
        ),
      ]);

      final loaded = await store.latestSleepSession();
      expect(loaded!.avgRespiratoryRateBrpm, isNull);
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
    test('wipes snapshots, sessions, watermark, and mode state', () async {
      final store = await openStore();
      final t = DateTime.utc(2026, 7, 15, 8, 0);
      await store.saveSnapshots([snap(t)]);
      await store.saveSleepSessions([night(t)]);
      await store.setLastSyncedUpTo(t);
      await store.saveModeState(EventModeConfig(
        id: ModeId.bigDay,
        targetDate: DateTime.utc(2026, 8, 1),
        startedAt: t,
      ));

      await store.deleteAllData();

      expect(await store.latestSnapshot(), isNull);
      expect(await store.latestSleepSession(), isNull);
      expect(await store.lastSyncedUpTo(), isNull);
      expect(await store.loadModeState(), isNull);
      await store.close();
    });

    test('wipes lifestyle mode rows too (night shift and fasting)',
        () async {
      final store = await openStore();
      await store.saveNightShiftState(NightShiftConfig(
        usualSleepStartHour: 9,
        usualSleepEndHour: 16,
        startedAt: DateTime.utc(2026, 7, 1),
      ));
      await store.saveFastingState(FastingConfig(
        type: FastType.roza,
        start: DateTime.utc(2026, 3, 1),
        end: DateTime.utc(2026, 3, 30),
        startedAt: DateTime.utc(2026, 2, 28),
      ));

      await store.deleteAllData();

      expect(await store.loadNightShiftState(), isNull);
      expect(await store.loadFastingState(), isNull);
      await store.close();
    });
  });

  group('Lifestyle mode state', () {
    test('night shift: null before starting, round-trips what was saved',
        () async {
      final store = await openStore();
      expect(await store.loadNightShiftState(), isNull);

      await store.saveNightShiftState(NightShiftConfig(
        usualSleepStartHour: 8,
        usualSleepEndHour: 15,
        startedAt: DateTime.utc(2026, 6, 1),
      ));

      final loaded = await store.loadNightShiftState();
      expect(loaded, isNotNull);
      expect(loaded!.usualSleepStartHour, 8);
      expect(loaded.usualSleepEndHour, 15);
      await store.close();
    });

    test('night shift: saving again replaces, not duplicates', () async {
      final store = await openStore();
      await store.saveNightShiftState(NightShiftConfig(
        usualSleepStartHour: 8,
        usualSleepEndHour: 15,
        startedAt: DateTime.utc(2026, 6, 1),
      ));
      await store.saveNightShiftState(NightShiftConfig(
        usualSleepStartHour: 10,
        usualSleepEndHour: 18,
        startedAt: DateTime.utc(2026, 6, 2),
      ));

      final loaded = await store.loadNightShiftState();
      expect(loaded!.usualSleepStartHour, 10);
      await store.close();
    });

    test('night shift: clearNightShiftState ends it', () async {
      final store = await openStore();
      await store.saveNightShiftState(NightShiftConfig(
        usualSleepStartHour: 8,
        usualSleepEndHour: 15,
        startedAt: DateTime.utc(2026, 6, 1),
      ));
      await store.clearNightShiftState();

      expect(await store.loadNightShiftState(), isNull);
      await store.close();
    });

    test('fasting: null before starting, round-trips what was saved',
        () async {
      final store = await openStore();
      expect(await store.loadFastingState(), isNull);

      await store.saveFastingState(FastingConfig(
        type: FastType.ekadashi,
        start: DateTime.utc(2026, 5, 5),
        end: DateTime.utc(2026, 5, 5),
        startedAt: DateTime.utc(2026, 5, 1),
      ));

      final loaded = await store.loadFastingState();
      expect(loaded, isNotNull);
      expect(loaded!.type, FastType.ekadashi);
      await store.close();
    });

    test('fasting: clearFastingState ends it', () async {
      final store = await openStore();
      await store.saveFastingState(FastingConfig(
        type: FastType.ekadashi,
        start: DateTime.utc(2026, 5, 5),
        end: DateTime.utc(2026, 5, 5),
        startedAt: DateTime.utc(2026, 5, 1),
      ));
      await store.clearFastingState();

      expect(await store.loadFastingState(), isNull);
      await store.close();
    });

    test(
        'an event mode, night shift, and fasting all coexist without '
        'interfering with each other', () async {
      final store = await openStore();

      await store.saveModeState(EventModeConfig(
        id: ModeId.bigDay,
        targetDate: DateTime.utc(2026, 8, 1),
        startedAt: DateTime.utc(2026, 7, 1),
      ));
      await store.saveNightShiftState(NightShiftConfig(
        usualSleepStartHour: 9,
        usualSleepEndHour: 16,
        startedAt: DateTime.utc(2026, 7, 1),
      ));
      await store.saveFastingState(FastingConfig(
        type: FastType.roza,
        start: DateTime.utc(2026, 3, 1),
        end: DateTime.utc(2026, 3, 30),
        startedAt: DateTime.utc(2026, 2, 28),
      ));

      expect((await store.loadModeState())?.id, ModeId.bigDay);
      expect((await store.loadNightShiftState())?.usualSleepStartHour, 9);
      expect((await store.loadFastingState())?.type, FastType.roza);

      // Ending the event mode must not touch the lifestyle rows.
      await store.clearModeState();
      expect(await store.loadModeState(), isNull);
      expect((await store.loadNightShiftState())?.usualSleepStartHour, 9);
      expect((await store.loadFastingState())?.type, FastType.roza);

      // Starting a NEW event mode must not touch the lifestyle rows
      // either — this is the case saveModeState's old "delete the
      // whole table" implementation would have broken.
      await store.saveModeState(EventModeConfig(
        id: ModeId.shaadi,
        targetDate: DateTime.utc(2026, 9, 1),
        startedAt: DateTime.utc(2026, 7, 2),
      ));
      expect((await store.loadNightShiftState())?.usualSleepStartHour, 9);
      expect((await store.loadFastingState())?.type, FastType.roza);

      await store.close();
    });
  });

  group('Event mode state', () {
    test('null before any mode starts, then round-trips what was saved',
        () async {
      final store = await openStore();
      expect(await store.loadModeState(), isNull);

      final config = EventModeConfig(
        id: ModeId.shaadi,
        targetDate: DateTime.utc(2026, 9, 10),
        label: "Priya's wedding",
        startedAt: DateTime.utc(2026, 8, 1),
      );
      await store.saveModeState(config);

      final loaded = await store.loadModeState();
      expect(loaded, isNotNull);
      expect(loaded!.id, ModeId.shaadi);
      expect(loaded.targetDate, config.targetDate);
      expect(loaded.label, "Priya's wedding");
      expect(loaded.startedAt, config.startedAt);
      await store.close();
    });

    test('starting a new mode replaces the old one, not both at once',
        () async {
      final store = await openStore();
      await store.saveModeState(EventModeConfig(
        id: ModeId.shaadi,
        targetDate: DateTime.utc(2026, 9, 10),
        startedAt: DateTime.utc(2026, 8, 1),
      ));
      await store.saveModeState(EventModeConfig(
        id: ModeId.examSeason,
        targetDate: DateTime.utc(2026, 10, 1),
        startedAt: DateTime.utc(2026, 8, 15),
      ));

      final loaded = await store.loadModeState();
      expect(loaded!.id, ModeId.examSeason,
          reason: 'only the most recently started mode should remain');
      await store.close();
    });

    test('clearModeState ends the active mode', () async {
      final store = await openStore();
      await store.saveModeState(EventModeConfig(
        id: ModeId.bigDay,
        targetDate: DateTime.utc(2026, 9, 10),
        startedAt: DateTime.utc(2026, 8, 1),
      ));
      await store.clearModeState();

      expect(await store.loadModeState(), isNull);
      await store.close();
    });
  });

  group('Schema migration v1 -> v2', () {
    test('opening an old v1 database preserves its data and adds '
        'mode_state', () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('hux_migration_');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'hux_v1.db');

      final snapshotTs = DateTime.utc(2026, 7, 1, 8, 0);
      final bedtime = DateTime.utc(2026, 6, 30, 23, 0);
      final wakeTime = bedtime.add(const Duration(hours: 7));
      final watermark = DateTime.utc(2026, 7, 1, 9, 0);

      // Step 1: build a v1 database by hand — this is exactly the
      // schema _createSchema had before mode_state existed. Simulates
      // a real device that installed the app before this migration.
      final v1Db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE snapshots (
                ts INTEGER PRIMARY KEY,
                hr INTEGER, hrv INTEGER, spo2 INTEGER, temp REAL, steps INTEGER
              )
            ''');
            await db.execute('''
              CREATE TABLE sleep_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                bedtime INTEGER NOT NULL UNIQUE,
                wake_time INTEGER NOT NULL,
                avg_hr INTEGER, avg_hrv INTEGER, min_spo2 INTEGER, avg_temp REAL
              )
            ''');
            await db.execute('''
              CREATE TABLE sleep_segments (
                session_id INTEGER NOT NULL
                  REFERENCES sleep_sessions(id) ON DELETE CASCADE,
                start_ts INTEGER NOT NULL,
                end_ts INTEGER NOT NULL,
                stage TEXT NOT NULL
              )
            ''');
            await db.execute(
                'CREATE INDEX idx_segments_session ON sleep_segments(session_id)');
            await db.execute('''
              CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)
            ''');
          },
        ),
      );

      await v1Db.insert('snapshots', {
        'ts': snapshotTs.millisecondsSinceEpoch,
        'hr': 60,
        'hrv': 50,
        'spo2': 97,
        'temp': 33.6,
        'steps': 4200,
      });
      final sessionId = await v1Db.insert('sleep_sessions', {
        'bedtime': bedtime.millisecondsSinceEpoch,
        'wake_time': wakeTime.millisecondsSinceEpoch,
        'avg_hr': 58,
        'avg_hrv': 52,
        'min_spo2': 95,
        'avg_temp': 33.5,
      });
      await v1Db.insert('sleep_segments', {
        'session_id': sessionId,
        'start_ts': bedtime.millisecondsSinceEpoch,
        'end_ts': wakeTime.millisecondsSinceEpoch,
        'stage': 'light',
      });
      await v1Db.insert('meta', {
        'key': 'last_synced_up_to',
        'value': watermark.millisecondsSinceEpoch.toString(),
      });
      await v1Db.close();

      // Step 2: reopen through SqliteHealthStore, which requests v2 —
      // sqflite calls onUpgrade(1, 2) under the hood.
      final store =
          await SqliteHealthStore.open(path, factory: databaseFactoryFfi);

      // Old data survived untouched.
      final snapshot = await store.latestSnapshot();
      expect(snapshot, isNotNull);
      expect(snapshot!.timestamp, snapshotTs);
      expect(snapshot.heartRateBpm, 60);
      expect(snapshot.steps, 4200);

      final session = await store.latestSleepSession();
      expect(session, isNotNull);
      expect(session!.bedtime, bedtime);
      expect(session.segments.single.stage, SleepStage.light);
      expect(session.avgHrvMs, 52);

      expect(await store.lastSyncedUpTo(), watermark);

      // New table works on the upgraded database.
      expect(await store.loadModeState(), isNull);
      await store.saveModeState(EventModeConfig(
        id: ModeId.bigDay,
        targetDate: DateTime.utc(2026, 8, 1),
        startedAt: DateTime.utc(2026, 7, 2),
      ));
      expect((await store.loadModeState())?.id, ModeId.bigDay);

      await store.close();
    });
  });

  group('Schema migration v2 -> v3', () {
    test('opening an old v2 database (no resp_rate/active_kcal/stress/'
        'avg_resp_rate columns) preserves its data and adds those columns '
        'as NULL for existing rows', () async {
      sqfliteFfiInit();
      final dir = await Directory.systemTemp.createTemp('hux_migration_v2_');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'hux_v2.db');

      final snapshotTs = DateTime.utc(2026, 7, 1, 8, 0);
      final bedtime = DateTime.utc(2026, 6, 30, 23, 0);
      final wakeTime = bedtime.add(const Duration(hours: 7));
      final watermark = DateTime.utc(2026, 7, 1, 9, 0);

      // Step 1: build a v2 database by hand — the schema _createSchema
      // had right before this migration added the new columns. Simulates
      // a real device that installed the app before this change.
      final v2Db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE snapshots (
                ts INTEGER PRIMARY KEY,
                hr INTEGER, hrv INTEGER, spo2 INTEGER, temp REAL, steps INTEGER
              )
            ''');
            await db.execute('''
              CREATE TABLE sleep_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                bedtime INTEGER NOT NULL UNIQUE,
                wake_time INTEGER NOT NULL,
                avg_hr INTEGER, avg_hrv INTEGER, min_spo2 INTEGER, avg_temp REAL
              )
            ''');
            await db.execute('''
              CREATE TABLE sleep_segments (
                session_id INTEGER NOT NULL
                  REFERENCES sleep_sessions(id) ON DELETE CASCADE,
                start_ts INTEGER NOT NULL,
                end_ts INTEGER NOT NULL,
                stage TEXT NOT NULL
              )
            ''');
            await db.execute(
                'CREATE INDEX idx_segments_session ON sleep_segments(session_id)');
            await db.execute('''
              CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)
            ''');
            await db.execute('''
              CREATE TABLE mode_state (
                mode_id TEXT PRIMARY KEY,
                json TEXT NOT NULL
              )
            ''');
          },
        ),
      );

      await v2Db.insert('snapshots', {
        'ts': snapshotTs.millisecondsSinceEpoch,
        'hr': 60,
        'hrv': 50,
        'spo2': 97,
        'temp': 33.6,
        'steps': 4200,
      });
      final sessionId = await v2Db.insert('sleep_sessions', {
        'bedtime': bedtime.millisecondsSinceEpoch,
        'wake_time': wakeTime.millisecondsSinceEpoch,
        'avg_hr': 58,
        'avg_hrv': 52,
        'min_spo2': 95,
        'avg_temp': 33.5,
      });
      await v2Db.insert('sleep_segments', {
        'session_id': sessionId,
        'start_ts': bedtime.millisecondsSinceEpoch,
        'end_ts': wakeTime.millisecondsSinceEpoch,
        'stage': 'light',
      });
      await v2Db.insert('meta', {
        'key': 'last_synced_up_to',
        'value': watermark.millisecondsSinceEpoch.toString(),
      });
      await v2Db.close();

      // Step 2: reopen through SqliteHealthStore, which requests v3 —
      // sqflite calls onUpgrade(2, 3) under the hood.
      final store =
          await SqliteHealthStore.open(path, factory: databaseFactoryFfi);

      // Old data survived untouched, and the new columns default to
      // null rather than 0 or throwing.
      final snapshot = await store.latestSnapshot();
      expect(snapshot, isNotNull);
      expect(snapshot!.timestamp, snapshotTs);
      expect(snapshot.heartRateBpm, 60);
      expect(snapshot.steps, 4200);
      expect(snapshot.respiratoryRateBrpm, isNull);
      expect(snapshot.activeEnergyKcal, isNull);
      expect(snapshot.stressIndex, isNull);

      final session = await store.latestSleepSession();
      expect(session, isNotNull);
      expect(session!.bedtime, bedtime);
      expect(session.avgHrvMs, 52);
      expect(session.avgRespiratoryRateBrpm, isNull);

      expect(await store.lastSyncedUpTo(), watermark);

      // The new columns accept writes on the upgraded database.
      await store.saveSnapshots([
        HealthSnapshot(
          timestamp: snapshotTs.add(const Duration(hours: 1)),
          respiratoryRateBrpm: 16,
          activeEnergyKcal: 200,
          stressIndex: 55,
        ),
      ]);
      final newSnapshot = await store.snapshotsBetween(
        snapshotTs.add(const Duration(minutes: 30)),
        snapshotTs.add(const Duration(hours: 2)),
      );
      expect(newSnapshot.single.respiratoryRateBrpm, 16);
      expect(newSnapshot.single.activeEnergyKcal, 200);
      expect(newSnapshot.single.stressIndex, 55);

      await store.close();
    });
  });
}
