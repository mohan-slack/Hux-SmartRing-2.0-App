/// HUX Mode Service
/// -----------------
/// Thin orchestrator: the only file in lib/core/modes/ allowed to
/// import storage. Loads the active [EventModeConfig], asks
/// [EventModeEngine] what to show, and — the one side effect the pure
/// engine can't have — clears the mode once it auto-completes.

import '../meaning/daily_readout.dart';
import '../storage/health_store.dart';
import 'event_mode_engine.dart';
import 'mode.dart';

class ModeService {
  final HealthStore _store;
  final EventModeEngine _engine;

  ModeService(this._store, {EventModeEngine engine = const EventModeEngine()})
      : _engine = engine;

  /// The active mode's config, or null if none is running.
  Future<EventModeConfig?> activeConfig() => _store.loadModeState();

  /// Starts (or replaces) the active event mode. Confirming the
  /// replace with the user is a UI concern (see ModesScreen) — this
  /// just performs it.
  Future<void> startMode(EventModeConfig config) =>
      _store.saveModeState(config);

  /// Ends the active mode, if any.
  Future<void> endMode() => _store.clearModeState();

  // ---- lifestyle modes ------------------------------------------------
  // Night Shift and Fasting each have at most one active config, but a
  // lifestyle mode can coexist with the active event mode above (and
  // with each other) — see mode.dart's doc comment on [LifestyleModeId].

  Future<void> startNightShift(NightShiftConfig config) =>
      _store.saveNightShiftState(config);

  Future<void> endNightShift() => _store.clearNightShiftState();

  Future<NightShiftConfig?> activeNightShift() => _store.loadNightShiftState();

  Future<void> startFasting(FastingConfig config) =>
      _store.saveFastingState(config);

  Future<void> endFasting() => _store.clearFastingState();

  Future<FastingConfig?> activeFasting() => _store.loadFastingState();

  /// Everything the Meaning engine and the screens need about which
  /// lifestyle modes are active right now, built fresh from storage —
  /// see [ActiveContext].
  Future<ActiveContext> activeContext({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final nightShift = await _store.loadNightShiftState();
    final fasting = await _store.loadFastingState();
    final fastingToday = fasting != null && fasting.isActiveOn(today);
    return ActiveContext(
      nightShiftActive: nightShift != null,
      nightShift: nightShift,
      fasting: fasting,
      fastDayNumber: fastingToday ? fasting.dayNumberOn(today) : null,
    );
  }

  /// The strip to show on Today, or null if no mode is active. When
  /// the active mode's target date has passed, this returns ONE final
  /// wrap-up strip and clears the mode so it won't show again.
  Future<ModeStrip?> currentStrip({
    required DailyReadout readout,
    DateTime? now,
  }) async {
    final config = await _store.loadModeState();
    if (config == null) return null;

    final today = now ?? DateTime.now();
    final strip = _engine.evaluate(config: config, today: today, readout: readout);

    if (strip.phase == ModePhase.completed) {
      await _store.clearModeState();
    }
    return strip;
  }
}
