/// SQLite implementation of [HealthStore].
/// ----------------------------------------
/// Schema decisions, recorded so nobody has to reverse-engineer them:
///
/// - `snapshots.ts` (epoch milliseconds, UTC) is the PRIMARY KEY.
///   That single choice makes saving idempotent at the database level:
///   duplicates cannot exist, no application-side dedupe code to get
///   wrong.
/// - Sleep sessions are unique on `bedtime`. Replacing a session
///   deletes and re-inserts its segments in one transaction, so a
///   reader can never observe a half-written night.
/// - All times are stored as UTC epoch ms and converted at the edges.
///   Timezones are a display concern, not a storage concern.
/// - `meta` is a tiny key-value table for the sync watermark and any
///   future flags. Not a dumping ground.

import 'package:sqflite/sqflite.dart';

import '../ring/ring_models.dart';
import 'health_store.dart';

class SqliteHealthStore implements HealthStore {
  final Database _db;

  SqliteHealthStore._(this._db);

  static const _schemaVersion = 1;

  /// Opens (and if needed creates) the database at [path].
  /// Pass an in-memory path in tests via sqflite_common_ffi.
  static Future<SqliteHealthStore> open(String path,
      {DatabaseFactory? factory}) async {
    final dbFactory = factory ?? databaseFactory;
    final db = await dbFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createSchema,
      ),
    );
    return SqliteHealthStore._(db);
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE snapshots (
        ts INTEGER PRIMARY KEY,
        hr INTEGER,
        hrv INTEGER,
        spo2 INTEGER,
        temp REAL,
        steps INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE sleep_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bedtime INTEGER NOT NULL UNIQUE,
        wake_time INTEGER NOT NULL,
        avg_hr INTEGER,
        avg_hrv INTEGER,
        min_spo2 INTEGER,
        avg_temp REAL
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
      CREATE TABLE meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  // ---- snapshots ----------------------------------------------------

  @override
  Future<int> saveSnapshots(List<HealthSnapshot> snapshots) async {
    if (snapshots.isEmpty) return 0;
    final batch = _db.batch();
    for (final s in snapshots) {
      batch.insert(
        'snapshots',
        {
          'ts': s.timestamp.toUtc().millisecondsSinceEpoch,
          'hr': s.heartRateBpm,
          'hrv': s.hrvMs,
          'spo2': s.spo2Percent,
          'temp': s.skinTempCelsius,
          'steps': s.steps,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    final results = await batch.commit(noResult: false);
    return results.length;
  }

  HealthSnapshot _snapshotFromRow(Map<String, Object?> r) => HealthSnapshot(
        timestamp: DateTime.fromMillisecondsSinceEpoch(r['ts'] as int,
            isUtc: true),
        heartRateBpm: r['hr'] as int?,
        hrvMs: r['hrv'] as int?,
        spo2Percent: r['spo2'] as int?,
        skinTempCelsius: (r['temp'] as num?)?.toDouble(),
        steps: r['steps'] as int?,
      );

  @override
  Future<List<HealthSnapshot>> snapshotsBetween(
      DateTime from, DateTime to) async {
    final rows = await _db.query(
      'snapshots',
      where: 'ts >= ? AND ts < ?',
      whereArgs: [
        from.toUtc().millisecondsSinceEpoch,
        to.toUtc().millisecondsSinceEpoch,
      ],
      orderBy: 'ts ASC',
    );
    return rows.map(_snapshotFromRow).toList();
  }

  @override
  Future<HealthSnapshot?> latestSnapshot() async {
    final rows = await _db.query('snapshots', orderBy: 'ts DESC', limit: 1);
    return rows.isEmpty ? null : _snapshotFromRow(rows.first);
  }

  // ---- sleep --------------------------------------------------------

  @override
  Future<int> saveSleepSessions(List<SleepSession> sessions) async {
    if (sessions.isEmpty) return 0;
    var saved = 0;
    await _db.transaction((txn) async {
      for (final session in sessions) {
        final bedtimeMs = session.bedtime.toUtc().millisecondsSinceEpoch;

        // Replace-by-bedtime: remove any previous version of this night.
        // Segments cascade-delete via the foreign key.
        await txn.delete('sleep_sessions',
            where: 'bedtime = ?', whereArgs: [bedtimeMs]);

        final sessionId = await txn.insert('sleep_sessions', {
          'bedtime': bedtimeMs,
          'wake_time': session.wakeTime.toUtc().millisecondsSinceEpoch,
          'avg_hr': session.avgHeartRateBpm,
          'avg_hrv': session.avgHrvMs,
          'min_spo2': session.minSpo2Percent,
          'avg_temp': session.avgSkinTempCelsius,
        });

        final batch = txn.batch();
        for (final seg in session.segments) {
          batch.insert('sleep_segments', {
            'session_id': sessionId,
            'start_ts': seg.start.toUtc().millisecondsSinceEpoch,
            'end_ts': seg.end.toUtc().millisecondsSinceEpoch,
            'stage': seg.stage.name,
          });
        }
        await batch.commit(noResult: true);
        saved++;
      }
    });
    return saved;
  }

  Future<List<SleepSession>> _sessionsFromRows(
      DatabaseExecutor db, List<Map<String, Object?>> rows) async {
    final sessions = <SleepSession>[];
    for (final r in rows) {
      final segRows = await db.query(
        'sleep_segments',
        where: 'session_id = ?',
        whereArgs: [r['id']],
        orderBy: 'start_ts ASC',
      );
      sessions.add(SleepSession(
        bedtime: DateTime.fromMillisecondsSinceEpoch(r['bedtime'] as int,
            isUtc: true),
        wakeTime: DateTime.fromMillisecondsSinceEpoch(
            r['wake_time'] as int,
            isUtc: true),
        segments: segRows
            .map((s) => SleepSegment(
                  start: DateTime.fromMillisecondsSinceEpoch(
                      s['start_ts'] as int,
                      isUtc: true),
                  end: DateTime.fromMillisecondsSinceEpoch(
                      s['end_ts'] as int,
                      isUtc: true),
                  stage: SleepStage.values.byName(s['stage'] as String),
                ))
            .toList(),
        avgHeartRateBpm: r['avg_hr'] as int?,
        avgHrvMs: r['avg_hrv'] as int?,
        minSpo2Percent: r['min_spo2'] as int?,
        avgSkinTempCelsius: (r['avg_temp'] as num?)?.toDouble(),
      ));
    }
    return sessions;
  }

  @override
  Future<List<SleepSession>> sleepSessionsBetween(
      DateTime from, DateTime to) async {
    final rows = await _db.query(
      'sleep_sessions',
      where: 'bedtime >= ? AND bedtime < ?',
      whereArgs: [
        from.toUtc().millisecondsSinceEpoch,
        to.toUtc().millisecondsSinceEpoch,
      ],
      orderBy: 'bedtime ASC',
    );
    return _sessionsFromRows(_db, rows);
  }

  @override
  Future<SleepSession?> latestSleepSession() async {
    final rows =
        await _db.query('sleep_sessions', orderBy: 'bedtime DESC', limit: 1);
    if (rows.isEmpty) return null;
    final list = await _sessionsFromRows(_db, rows);
    return list.first;
  }

  // ---- sync watermark ----------------------------------------------

  static const _watermarkKey = 'last_synced_up_to';

  @override
  Future<DateTime?> lastSyncedUpTo() async {
    final rows = await _db
        .query('meta', where: 'key = ?', whereArgs: [_watermarkKey]);
    if (rows.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(
        int.parse(rows.first['value'] as String),
        isUtc: true);
  }

  @override
  Future<void> setLastSyncedUpTo(DateTime instant) async {
    await _db.insert(
      'meta',
      {
        'key': _watermarkKey,
        'value': instant.toUtc().millisecondsSinceEpoch.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---- lifecycle ----------------------------------------------------

  @override
  Future<void> deleteAllData() async {
    await _db.transaction((txn) async {
      await txn.delete('sleep_segments');
      await txn.delete('sleep_sessions');
      await txn.delete('snapshots');
      await txn.delete('meta');
    });
  }

  @override
  Future<void> close() => _db.close();
}
