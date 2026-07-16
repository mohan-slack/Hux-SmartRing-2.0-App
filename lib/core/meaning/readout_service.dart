/// HUX Readout Service
/// --------------------
/// Thin orchestrator: the only file in lib/core/meaning/ allowed to
/// import storage. Loads what [MeaningEngine] needs, calls it, hands
/// back a [DailyReadout]. Contains no scoring logic itself.

import '../ring/ring_models.dart';
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

  /// How stale the latest sleep session may be and still count as "last
  /// night". A user who hasn't synced in days must not have a 3-day-old
  /// night presented as fresh insight — that's stale data dressed up as
  /// today's readout. 36h covers a late sleeper / delayed sync without
  /// letting genuinely old data pass as current.
  static const staleNightThreshold = Duration(hours: 36);

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

    final lastNight = await this.lastNight(now: reference);

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

  /// The most recent sleep session, if it's recent enough to honestly
  /// count as "last night" — see [staleNightThreshold]. Public so the UI
  /// can render last night's raw numbers using the exact same staleness
  /// rule [today] scores against, instead of duplicating it.
  Future<SleepSession?> lastNight({DateTime? now}) async {
    final reference = (now ?? DateTime.now()).toUtc();
    final session = await _store.latestSleepSession();
    if (session == null) return null;
    final age = reference.difference(session.wakeTime.toUtc());
    return age <= staleNightThreshold ? session : null;
  }
}
