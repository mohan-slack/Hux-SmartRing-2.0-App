/// HUX Health Store Interface
/// --------------------------
/// The contract for persisting ring data on the phone.
///
/// Rules it enforces (wiki page 6):
/// - Write first, sync second. The phone is the source of truth.
/// - Saving is IDEMPOTENT: the same reading saved twice is stored once.
///   The sync layer re-fetches overlapping windows on purpose; the
///   store's job is to make that harmless.
/// - No health data leaves the phone in v1. This interface has no
///   network concepts at all — that is deliberate.

import '../modes/mode.dart';
import '../ring/ring_models.dart';

abstract class HealthStore {
  /// Persist snapshots. Duplicate timestamps are resolved by REPLACE:
  /// if the ring re-sends a reading for the same instant (e.g. a
  /// recomputed value on a later sync), the newer write wins. The ring
  /// is the source of truth for its own readings.
  Future<int> saveSnapshots(List<HealthSnapshot> snapshots);

  /// Persist sleep sessions. A session is identified by its bedtime;
  /// re-saving a session replaces it and its segments atomically.
  Future<int> saveSleepSessions(List<SleepSession> sessions);

  /// Snapshots in [from, to), oldest first.
  Future<List<HealthSnapshot>> snapshotsBetween(DateTime from, DateTime to);

  /// The most recent snapshot, or null if the store is empty.
  Future<HealthSnapshot?> latestSnapshot();

  /// Sleep sessions whose bedtime falls in [from, to), oldest first.
  Future<List<SleepSession>> sleepSessionsBetween(DateTime from, DateTime to);

  /// The most recent sleep session, or null.
  Future<SleepSession?> latestSleepSession();

  /// Sync watermark: the instant up to which we have synced from the
  /// ring. Null before the first ever sync.
  Future<DateTime?> lastSyncedUpTo();
  Future<void> setLastSyncedUpTo(DateTime instant);

  /// Wipe everything. Used by "delete my data" (a DPDP requirement)
  /// and by tests. Irreversible by design.
  Future<void> deleteAllData();

  /// Persists the active event mode, replacing whatever was active
  /// before — at most one event mode is ever active at a time. Never
  /// touches lifestyle mode rows (night shift, fasting) — those coexist.
  Future<void> saveModeState(EventModeConfig config);

  /// The active event mode, or null if none is running.
  Future<EventModeConfig?> loadModeState();

  /// Ends the active mode, if any. A no-op if none is running.
  Future<void> clearModeState();

  /// Persists (or replaces) the active Night Shift lifestyle mode.
  Future<void> saveNightShiftState(NightShiftConfig config);
  Future<NightShiftConfig?> loadNightShiftState();
  Future<void> clearNightShiftState();

  /// Persists (or replaces) the active Fasting Companion lifestyle mode.
  Future<void> saveFastingState(FastingConfig config);
  Future<FastingConfig?> loadFastingState();
  Future<void> clearFastingState();

  Future<void> close();
}
