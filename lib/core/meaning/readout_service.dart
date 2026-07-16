/// HUX Readout Service
/// --------------------
/// Thin orchestrator: the only file in lib/core/meaning/ allowed to
/// import storage. Loads what [MeaningEngine] needs, calls it, hands
/// back a [DailyReadout]. Contains no scoring logic itself.

import '../storage/health_store.dart';
import 'baseline.dart';
import 'daily_readout.dart';
import 'meaning_engine.dart';

class ReadoutService {
  final HealthStore _store;
  final MeaningEngine _engine;

  /// Baseline window: how many days of history feed the personal
  /// baseline. Matches the wiki's "14 days is enough, 7 is thin" call.
  static const baselineWindow = Duration(days: 14);

  ReadoutService(this._store, {MeaningEngine engine = const MeaningEngine()})
      : _engine = engine;

  /// Builds today's readout from whatever is currently in the store.
  /// [now] is injectable for tests; defaults to the real clock.
  Future<DailyReadout> today({DateTime? now}) async {
    final reference = (now ?? DateTime.now()).toUtc();

    final history = await _store.sleepSessionsBetween(
      reference.subtract(baselineWindow),
      reference,
    );
    final baseline = PersonalBaseline.fromSleepSessions(history);

    final lastNight = await _store.latestSleepSession();

    final todayStart =
        DateTime.utc(reference.year, reference.month, reference.day);
    final todaySnapshots =
        await _store.snapshotsBetween(todayStart, reference);

    return _engine.evaluate(
      date: DateTime(reference.year, reference.month, reference.day),
      baseline: baseline,
      lastNight: lastNight,
      todaySnapshots: todaySnapshots,
    );
  }
}
