/// HUX Sync Service
/// ----------------
/// Orchestrates one job: get everything the ring knows into local
/// storage without losing a reading. Sits between [RingAdapter] and
/// [HealthStore]; knows nothing about vendors or SQL.
///
/// Design decisions, recorded:
///
/// - OVERLAP: every sync re-fetches a window BEFORE the watermark
///   (default 1 hour). Clocks drift, BLE writes get interrupted, rings
///   recompute values. Re-fetching overlap costs a little battery;
///   a gap costs a user's night of sleep data. The store's idempotent
///   writes make the overlap harmless.
/// - RETRY: BLE fails routinely, so failure is retried with backoff,
///   quietly. Only after all retries does the caller see a failure.
/// - FIRST SYNC: with no watermark, we pull [firstSyncWindow]
///   (default 7 days) — enough for the Meaning engine to build a
///   baseline, small enough to keep the first sync fast.
/// - The watermark only advances AFTER a successful save. A crash
///   between fetch and save means the same data is fetched again next
///   time — duplicates are free, gaps are not.

import 'dart:async';

import '../ring/ring_adapter.dart';
import '../ring/ring_models.dart';
import '../storage/health_store.dart';

/// What a sync attempt produced.
class SyncOutcome {
  final bool success;
  final int snapshotsSaved;
  final int sleepSessionsSaved;
  final int attemptsUsed;
  final String? error;

  const SyncOutcome({
    required this.success,
    this.snapshotsSaved = 0,
    this.sleepSessionsSaved = 0,
    this.attemptsUsed = 1,
    this.error,
  });

  @override
  String toString() => success
      ? 'SyncOutcome(ok: $snapshotsSaved snapshots, '
          '$sleepSessionsSaved nights, attempts: $attemptsUsed)'
      : 'SyncOutcome(failed after $attemptsUsed attempts: $error)';
}

/// Coarse status for the UI. Render calmly — syncing and retrying are
/// normal states, not alarms.
enum SyncPhase { idle, connecting, syncing, saving, done, failed }

class SyncStatus {
  final SyncPhase phase;
  final int attempt;
  const SyncStatus(this.phase, {this.attempt = 1});
}

class SyncService {
  final RingAdapter _ring;
  final HealthStore _store;
  final Duration overlap;
  final Duration firstSyncWindow;
  final int maxAttempts;
  final Duration baseBackoff;

  final _status = StreamController<SyncStatus>.broadcast();
  bool _syncInProgress = false;

  /// The [RingInfo] returned by the most recent successful `connect()` —
  /// captured here (rather than discarded) so the UI has an immediate,
  /// correct reading (e.g. battery) right after a sync, without waiting
  /// on [batteryPercent]'s live stream, which some adapters only feed
  /// stochastically over time.
  RingInfo? lastRingInfo;

  /// Live battery updates, straight from the connected [RingAdapter].
  /// [RingAdapter] itself stays fully encapsulated behind this service —
  /// screens never see it directly, same rule as everything else here.
  Stream<int> get batteryPercent => _ring.batteryPercent;

  /// Live heart-rate readings, straight from [RingAdapter.liveSnapshots]
  /// — for the Today screen's vivid Heart Rate highlight card, which
  /// wants an instantaneous reading rather than last night's overnight
  /// average. Nullable per snapshot, same as [HealthSnapshot.heartRateBpm]
  /// itself: a snapshot with no HR reading (motion, poor contact) is
  /// normal, not an error.
  Stream<int?> get heartRateBpm => _ring.liveSnapshots.map((s) => s.heartRateBpm);

  /// Sends one real vibration to the ring, for a "test my ring" UI
  /// affordance. Throws [RingConnectionException] when not connected,
  /// same as every other [RingAdapter] method — callers use the same
  /// try/catch-and-snackbar pattern already used for sync failures.
  Future<void> sendTestBuzz() => _ring.vibrate();

  SyncService(
    this._ring,
    this._store, {
    this.overlap = const Duration(hours: 1),
    this.firstSyncWindow = const Duration(days: 7),
    this.maxAttempts = 3,
    this.baseBackoff = const Duration(seconds: 2),
  });

  Stream<SyncStatus> get status => _status.stream;

  /// Run one full sync. Safe to call from a button, a timer, or an
  /// OS background task. Re-entrant calls while a sync is running
  /// return a failed outcome instead of racing.
  Future<SyncOutcome> syncNow() async {
    if (_syncInProgress) {
      return const SyncOutcome(
          success: false, error: 'Sync already in progress');
    }
    _syncInProgress = true;
    try {
      return await _syncWithRetry();
    } finally {
      _syncInProgress = false;
    }
  }

  Future<SyncOutcome> _syncWithRetry() async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final outcome = await _syncOnce(attempt);
        _status.add(const SyncStatus(SyncPhase.done));
        return outcome;
      } on RingConnectionException catch (e) {
        lastError = e;
        if (attempt < maxAttempts) {
          // Exponential backoff: 2s, 4s, 8s...
          await Future.delayed(baseBackoff * (1 << (attempt - 1)));
        }
      }
    }
    _status.add(SyncStatus(SyncPhase.failed, attempt: maxAttempts));
    return SyncOutcome(
      success: false,
      attemptsUsed: maxAttempts,
      error: lastError.toString(),
    );
  }

  Future<SyncOutcome> _syncOnce(int attempt) async {
    _status.add(SyncStatus(SyncPhase.connecting, attempt: attempt));
    lastRingInfo = await _ring.connect();

    _status.add(SyncStatus(SyncPhase.syncing, attempt: attempt));
    final watermark = await _store.lastSyncedUpTo();
    final since = watermark == null
        ? DateTime.now().toUtc().subtract(firstSyncWindow)
        : watermark.subtract(overlap);

    final result = await _ring.syncSince(since);

    _status.add(SyncStatus(SyncPhase.saving, attempt: attempt));
    // Save FIRST, advance the watermark LAST. Order is the guarantee.
    final snapshotsSaved = await _store.saveSnapshots(result.snapshots);
    final sessionsSaved =
        await _store.saveSleepSessions(result.sleepSessions);
    await _store.setLastSyncedUpTo(result.syncedUpTo);

    return SyncOutcome(
      success: true,
      snapshotsSaved: snapshotsSaved,
      sleepSessionsSaved: sessionsSaved,
      attemptsUsed: attempt,
    );
  }

  Future<void> dispose() async {
    await _status.close();
  }
}
