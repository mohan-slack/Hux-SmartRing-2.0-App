/// HUX Readout Service
/// --------------------
/// Thin orchestrator: the only file in lib/core/meaning/ allowed to
/// import storage. Loads what [MeaningEngine] needs, calls it, hands
/// back a [DailyReadout]. Contains no scoring logic itself.

import '../modes/mode.dart';
import '../modes/mode_service.dart';
import '../ring/ring_models.dart';
import '../storage/health_store.dart';
import 'baseline.dart';
import 'content/fasting_content.dart';
import 'daily_readout.dart';
import 'meaning_engine.dart';

class ReadoutService {
  final HealthStore _store;
  final ModeService? _modeService;
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

  /// [modeService] is optional so existing callers (and every test that
  /// doesn't care about lifestyle modes) are unaffected — without it,
  /// [today] behaves exactly as before (no Night Shift wording swap, no
  /// Fasting Companion filtering/content). The composition root passes
  /// a real one; see main.dart.
  ReadoutService(
    this._store, {
    ModeService? modeService,
    MeaningEngine engine = const MeaningEngine(),
  })  : _modeService = modeService,
        _engine = engine;

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

    final context = _modeService == null
        ? const ActiveContext()
        : await _modeService.activeContext(now: reference);
    final fastingToday = context.fastingActiveOn(reference);

    final readout = _engine.evaluate(
      date: DateTime(reference.year, reference.month, reference.day),
      baseline: baseline,
      lastNight: lastNight,
      todaySnapshots: todaySnapshots,
      nightShiftActive: context.nightShiftActive,
      excludeDaytimeFood: fastingToday,
    );

    if (!fastingToday || readout.state == RecoveryState.learning) {
      return readout;
    }

    // Layer in ONE fasting-specific action, the same way the engine
    // already swaps in a temperature-specific one — MeaningEngine stays
    // generic (it only ever sees `excludeDaytimeFood`, a bool), so the
    // Fasting Companion copy pack lives here, at the service layer.
    final fasting = context.fasting!;
    final extra = FastingContent.pickForDay(
      fasting.type,
      context.fastDayNumber!,
      reference,
      eatingWindowStartHour: fasting.eatingWindowStartHour,
      eatingWindowEndHour: fasting.eatingWindowEndHour,
    );
    final actions = [...readout.actions];
    if (actions.length >= 2) {
      actions[actions.length - 1] = extra;
    } else {
      actions.add(extra);
    }

    return DailyReadout(
      date: readout.date,
      state: readout.state,
      headline: readout.headline,
      meaning: readout.meaning,
      actions: actions,
      dataQuality: readout.dataQuality,
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
