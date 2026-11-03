/// HUX Readout Service
/// --------------------
/// Thin orchestrator: the only file in lib/core/meaning/ allowed to
/// import storage. Loads what [MeaningEngine] needs, calls it, hands
/// back a [DailyReadout]. Contains no scoring logic itself.

import '../checkin/sleep_checkin.dart';
import '../cycle/cycle_models.dart';
import '../cycle/cycle_service.dart';
import '../modes/mode.dart';
import '../modes/mode_service.dart';
import '../profile/profile_service.dart';
import '../ring/ring_models.dart';
import '../storage/health_store.dart';
import 'baseline.dart';
import 'day_plan.dart';
import 'hux_charge.dart';
import 'step_goal_log.dart';
import 'step_target.dart';
import 'content/fasting_content.dart';
import 'daily_readout.dart';
import 'meaning_engine.dart';
import 'profile_tuning.dart';

class ReadoutService {
  final HealthStore _store;
  final ModeService? _modeService;
  final MeaningEngine _engine;

  /// Optional: when Cycle is on, the baseline compares the user with her
  /// OWN same-phase days (luteal vs the rest), so a normal pre-period
  /// rise in resting heart rate isn't read as "run down".
  final CycleService? _cycle;

  /// How far back to look for same-phase nights.
  static const cycleBaselineWindow = Duration(days: 90);

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
    CycleService? cycle,
  })  : _modeService = modeService,
        _engine = engine,
        _cycle = cycle;

  /// Builds today's readout from whatever is currently in the store.
  /// [now] is injectable for tests; defaults to the real clock.
  Future<DailyReadout> today({DateTime? now}) async {
    final reference = (now ?? DateTime.now()).toUtc();

    // Synced nights plus morning check-ins for nights the health app
    // doesn't have (phone-only users).
    final checkIns = await _checkIns();
    final history = SleepCheckInService.merge(
      await _store.sleepSessionsBetween(reference.subtract(baselineWindow), reference),
      [
        for (final c in checkIns)
          if (!c.wake.toUtc().isBefore(reference.subtract(baselineWindow)) && !c.wake.toUtc().isAfter(reference)) c,
      ],
    );
    final baseline = await _cycleBaseline(reference) ?? PersonalBaseline.fromSleepSessions(history);

    final lastNight = await this.lastNight(now: reference);

    // "Today" is the user's LOCAL day: in IST, UTC midnight is 05:30 AM,
    // which used to drop everything from local midnight to 05:30.
    final localNow = reference.toLocal();
    final todayStart =
        DateTime(localNow.year, localNow.month, localNow.day).toUtc();
    final todaySnapshots =
        await _store.snapshotsBetween(todayStart, reference);

    final context = _modeService == null
        ? const ActiveContext()
        : await _modeService.activeContext(now: reference);
    final fastingToday = context.fastingActiveOn(reference);

    Rested? feel;
    if (lastNight != null) {
      for (final c in checkIns.reversed) {
        if (c.wake.difference(lastNight.wakeTime).abs() <= const Duration(hours: 3)) {
          feel = c.feel;
          break;
        }
      }
    }
    final charge = const HuxChargeCalculator().calculate(
      baseline: baseline,
      lastNight: lastNight,
      todaySnapshots: todaySnapshots,
      now: reference,
      feel: feel?.score,
    );
    // Onboarding answers tune the plan (sleep minimum, gentler wording).
    var tuning = ProfileTuning.standard;
    try {
      tuning = ProfileTuning.of(await ProfileService(_store).loadProfile());
    } catch (_) {
      // No profile yet: standard plan.
    }
    final basePlan = const DayPlanner().plan(
      charge: charge,
      baseline: baseline,
      lastNight: lastNight,
      now: reference,
      minSleep: tuning.minSleep,
      usualWakeMinute: DayPlanner.usualWakeMinute(history),
      gentle: tuning.gentleEffort,
    );
    // Steps: the last week of days plus today (cumulative per day).
    final stepSnapshots = await _store.snapshotsBetween(
      todayStart.subtract(
          const Duration(days: StepTargetCalculator.historyDays)),
      reference,
    );
    final plan = basePlan.withSteps(const StepTargetCalculator().calculate(
      snapshots: stepSnapshots,
      now: reference,
      effort: basePlan.effort?.level,
    ));
    // Remember the goal shown today, so streaks/monthly use the same one.
    final shownGoal = plan.steps?.target;
    if (shownGoal != null) {
      try {
        await StepGoalLog(_store)
            .record(DateTime(localNow.year, localNow.month, localNow.day), shownGoal);
      } catch (_) {
        // Bookkeeping only — never block the readout.
      }
    }

    final readout = _engine.evaluate(
      date: DateTime(localNow.year, localNow.month, localNow.day),
      baseline: baseline,
      lastNight: lastNight,
      todaySnapshots: todaySnapshots,
      nightShiftActive: context.nightShiftActive,
      excludeDaytimeFood: fastingToday,
      stateOverride: charge.morningCharge == null ? null : MeaningEngine.stateForCharge(charge.morningCharge!),
    );

    // Never had ANY sleep: a phone-only user. Don't say "learning" with
    // nothing to learn from — point at what works and how to get more.
    if (history.isEmpty && readout.state == RecoveryState.learning) {
      final steps = plan.steps;
      return DailyReadout.noSleepYet(
        readout.date,
        stepsToday: steps?.today,
        stepGoal: steps?.target,
      ).withCharge(charge, plan: plan);
    }

    if (!fastingToday || readout.state == RecoveryState.learning) {
      return readout.withCharge(charge, plan: plan);
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
      stressIndex: readout.stressIndex,
      activeEnergyKcal: readout.activeEnergyKcal,
      currentHeartRateBpm: readout.currentHeartRateBpm,
      charge: charge,
      plan: plan,
    );
  }

  /// Same-phase baseline, or null to use the normal one (Cycle off, no
  /// phase today, or fewer than [PersonalBaseline.minDaysRequired] nights).
  Future<PersonalBaseline?> _cycleBaseline(DateTime reference) async {
    final cycle = _cycle;
    if (cycle == null) return null;
    try {
      final resolver = await cycle.resolver();
      if (resolver == null) return null;
      final todayPhase = resolver.phaseOn(reference.toLocal());
      if (todayPhase == null) return null;
      final luteal = todayPhase == CyclePhase.luteal;
      final longer = await _store.sleepSessionsBetween(reference.subtract(cycleBaselineWindow), reference);
      final matched = PersonalBaseline.mainSleepPerDay(longer).where((s) {
        final p = resolver.phaseOn(s.wakeTime.toLocal());
        return p != null && (p == CyclePhase.luteal) == luteal;
      }).toList();
      final recent = matched.length > 14 ? matched.sublist(matched.length - 14) : matched;
      final b = PersonalBaseline.fromSleepSessions(recent);
      return b.insufficient ? null : b;
    } catch (_) {
      return null; // never block the readout
    }
  }

  /// The most recent sleep session, if it's recent enough to honestly
  /// count as "last night" — see [staleNightThreshold]. Public so the UI
  /// can render last night's raw numbers using the exact same staleness
  /// rule [today] scores against, instead of duplicating it.
  Future<SleepSession?> lastNight({DateTime? now}) async {
    final reference = (now ?? DateTime.now()).toUtc();
    bool fresh(SleepSession s) {
      final age = reference.difference(s.wakeTime.toUtc());
      return !age.isNegative && age <= staleNightThreshold;
    }

    final synced = await _store.latestSleepSession();
    final checkIn = (await _checkIns()).where((c) => !c.fromDevice).lastOrNull?.toSession();
    final s = synced != null && fresh(synced) ? synced : null;
    final c = checkIn != null && fresh(checkIn) ? checkIn : null;
    if (s == null) return c;
    if (c == null) return s;
    // Both: a synced night wins for the same night; a newer check-in
    // (the watch missed last night) wins over an older synced one.
    final overlap = s.bedtime.isBefore(c.wakeTime) && s.wakeTime.isAfter(c.bedtime);
    return overlap || !c.wakeTime.isAfter(s.wakeTime) ? s : c;
  }

  Future<List<SleepCheckIn>> _checkIns() async {
    try {
      return await SleepCheckInService(_store).all();
    } catch (_) {
      return const [];
    }
  }
}
