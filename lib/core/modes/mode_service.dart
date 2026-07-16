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
