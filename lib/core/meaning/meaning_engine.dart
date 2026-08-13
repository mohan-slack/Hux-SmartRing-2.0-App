/// HUX Meaning Engine
/// -------------------
/// Numbers -> Meaning -> Action, rules-based, v1.
///
/// PURE DART. No Flutter imports, no I/O, no store access — everything
/// this file needs is passed in. Same inputs always produce the same
/// [DailyReadout]. [ReadoutService] is the only thing allowed to fetch
/// data and hand it to this engine.
///
/// Every threshold below is a NAMED CONSTANT with a comment explaining
/// what it means, so a human (not just an engineer) can tune the feel
/// of the product without reading scoring logic. All of them are
/// relative to the user's OWN [PersonalBaseline] — never a population
/// norm. The one exception is the deep-sleep floor, which is a coarse
/// physiological sanity check used only as a secondary, downward-only
/// nudge; the primary driver of every state is always personal-baseline
/// comparison.
///
/// Wellness wording only: nothing here may name a disease, diagnose, or
/// alarm. Worst-case language is "your body is working harder than
/// usual" — see the acceptance checklist in the README.

import '../ring/ring_models.dart';
import 'baseline.dart';
import 'content/action_content.dart';
import 'daily_readout.dart';
import 'sleep_wording.dart';

class MeaningEngine {
  // ---- HRV signal: last night's avgHrvMs vs baseline median ----------
  /// 10%+ above baseline reads as a good recovery signal.
  static const hrvGoodPct = 0.10;
  /// 10-25% below baseline reads as mildly stretched.
  static const hrvStretchedPct = 0.10;
  /// More than 25% below baseline reads as strained.
  static const hrvStrainedPct = 0.25;

  // ---- Sleep-duration signal: last night's totalSleep vs baseline -----
  static const sleepGoodPct = 0.10;
  static const sleepStretchedPct = 0.15;
  static const sleepStrainedPct = 0.30;
  /// Secondary check, not baseline-relative: if deep sleep makes up less
  /// than this fraction of total sleep, nudge the sleep signal down one
  /// step (never up). Guards against "long but shallow" nights that a
  /// pure duration comparison would miss.
  static const minDeepSleepFraction = 0.10;

  // ---- Resting HR signal: last night's avgHeartRateBpm vs baseline ----
  /// HR at least 5% below baseline reads as good (better-than-usual
  /// overnight recovery).
  static const hrGoodPct = 0.05;
  static const hrStretchedPct = 0.08;
  static const hrStrainedPct = 0.15;

  // ---- Skin temperature signal ----------------------------------------
  /// Absolute deviation from the user's own baseline. Wellness flag
  /// only — never treated as a medical reading.
  static const tempFlagDeltaC = 0.5;

  // ---- Respiratory-rate signal: SECONDARY, DOWNWARD-ONLY -------------
  /// Overnight breaths-per-minute more than this far ABOVE the user's
  /// own baseline nudges the score down one step. Mirrors [_scoreTemp]:
  /// a flag, not a primary driver — it can never raise the score (see
  /// [_scoreRespRate]).
  static const respRateFlagDeltaBrpm = 2.0;

  // ---- Signal weights (how much each moves the combined score) -------
  static const hrvWeight = 2;
  static const sleepWeight = 2;
  static const hrWeight = 1;
  static const tempWeight = 1;
  static const respRateWeight = 1;

  // ---- Derived stress (DISPLAY ONLY, never scored) --------------------
  /// HRV depressed this fraction or more below the user's own baseline
  /// reads as maximum (100) daytime stress; 0 fraction (HRV at or above
  /// baseline) reads as 0. Linear in between. This number is NEVER
  /// added to the recovery-score total — HRV already drives that via
  /// [hrvWeight]; folding a stress figure computed FROM the same HRV
  /// data back into the score would double-count one signal.
  static const stressHrvDepressionCeilingPct = 0.40;

  // ---- Combined-score cutoffs for the overall RecoveryState -----------
  static const rechargedThreshold = 3;
  static const steadyThreshold = 0;
  static const stretchedThreshold = -4;
  // Below stretchedThreshold => rundown.

  const MeaningEngine();

  /// Evaluate one day. [date] is passed in explicitly (not read from the
  /// system clock) so the engine stays a pure function of its inputs.
  ///
  /// [nightShiftActive] and [excludeDaytimeFood] are plain booleans, not
  /// the lifestyle-mode types themselves — deciding "is a lifestyle mode
  /// active" is a storage-touching question for [ReadoutService]; this
  /// engine only ever needs the yes/no answer, keeping it free of any
  /// dependency on core/modes.
  DailyReadout evaluate({
    required DateTime date,
    required PersonalBaseline baseline,
    required SleepSession? lastNight,
    required List<HealthSnapshot> todaySnapshots,
    bool nightShiftActive = false,
    bool excludeDaytimeFood = false,
  }) {
    if (baseline.insufficient) {
      return DailyReadout.learning(date, daysOfData: baseline.daysOfData);
    }

    // Display-only figures, computed regardless of whether last night's
    // sleep signals below are usable — a night with no usable sleep
    // data doesn't mean today's daytime snapshots are unusable too.
    final stressIndex = _deriveStress(baseline, todaySnapshots);
    final activeEnergyKcal = _todayActiveEnergyKcal(todaySnapshots);
    final currentHeartRateBpm = _todayHeartRateBpm(todaySnapshots);

    final hrvScore = _scoreHrv(baseline, lastNight);
    final sleepScore = _scoreSleep(baseline, lastNight);
    final hrScore = _scoreRestingHr(baseline, lastNight);
    final tempScore = _scoreTemp(baseline, lastNight);
    final respRateScore = _scoreRespRate(baseline, lastNight);

    final considered = [hrvScore, sleepScore, hrScore, tempScore]
        .where((s) => s != null)
        .length;

    if (considered == 0) {
      return DailyReadout.noSignal(date,
          stressIndex: stressIndex,
          activeEnergyKcal: activeEnergyKcal,
          currentHeartRateBpm: currentHeartRateBpm);
    }

    var total = 0;
    if (hrvScore != null) total += hrvScore * hrvWeight;
    if (sleepScore != null) total += sleepScore * sleepWeight;
    if (hrScore != null) total += hrScore * hrWeight;
    if (tempScore != null) total += tempScore * tempWeight;
    // respRateScore is only ever 0 or -1 (see _scoreRespRate) — a
    // downward nudge only, never a reason the total goes up. Left OUT
    // of `considered`/dataQuality on purpose: that count feeds the
    // "full" data-quality cutoff below, and respiratory data is newer/
    // rarer than the other four signals — counting it would mean a
    // night WITH respiratory data needs 5/5 for `full` instead of 4/4,
    // so having MORE data would perversely read as LOWER quality.
    if (respRateScore != null) total += respRateScore * respRateWeight;

    final state = _stateFromTotal(total);
    final quality = considered == 4
        ? DataQuality.full
        : (considered >= 2 ? DataQuality.partial : DataQuality.sparse);

    final composed = _compose(state,
        date: date,
        hrvScore: hrvScore,
        sleepScore: sleepScore,
        hrScore: hrScore,
        tempScore: tempScore,
        respRateScore: respRateScore,
        wording: SleepWording(nightShiftActive: nightShiftActive),
        excludeDaytimeFood: excludeDaytimeFood);

    return DailyReadout(
      date: date,
      state: state,
      headline: composed.headline,
      meaning: composed.meaning,
      actions: composed.actions,
      dataQuality: quality,
      stressIndex: stressIndex,
      activeEnergyKcal: activeEnergyKcal,
      currentHeartRateBpm: currentHeartRateBpm,
    );
  }

  // ---- signal scoring: each returns -2..+1, or null if unavailable ----
  // Missing inputs are skipped, never guessed — that's the caller's job
  // to reflect in dataQuality, which this method does via `considered`.

  int? _scoreHrv(PersonalBaseline baseline, SleepSession? lastNight) {
    final base = baseline.medianHrvMs;
    final last = lastNight?.avgHrvMs;
    if (base == null || last == null || base == 0) return null;
    final diff = (last - base) / base;
    if (diff >= hrvGoodPct) return 1;
    if (diff <= -hrvStrainedPct) return -2;
    if (diff <= -hrvStretchedPct) return -1;
    return 0;
  }

  int? _scoreSleep(PersonalBaseline baseline, SleepSession? lastNight) {
    final base = baseline.medianTotalSleep;
    // Empty segments means no sleep was recorded at all — a gap, not a
    // reading of zero minutes — so treat it the same as no session.
    if (lastNight == null || lastNight.segments.isEmpty) return null;
    final last = lastNight.totalSleep;
    if (base == null || base.inMinutes == 0) return null;

    final diff = (last.inMinutes - base.inMinutes) / base.inMinutes;
    var score = 0;
    if (diff >= sleepGoodPct) {
      score = 1;
    } else if (diff <= -sleepStrainedPct) {
      score = -2;
    } else if (diff <= -sleepStretchedPct) {
      score = -1;
    }

    final totalMinutes = last.inMinutes;
    if (totalMinutes > 0) {
      final deepMinutes = lastNight.stageTotal(SleepStage.deep).inMinutes;
      if (deepMinutes / totalMinutes < minDeepSleepFraction) {
        score = (score - 1).clamp(-2, 1);
      }
    }
    return score;
  }

  int? _scoreRestingHr(PersonalBaseline baseline, SleepSession? lastNight) {
    final base = baseline.medianRestingHeartRateBpm;
    final last = lastNight?.avgHeartRateBpm;
    if (base == null || last == null || base == 0) return null;
    final diff = (last - base) / base; // positive = elevated = worse
    if (diff <= -hrGoodPct) return 1;
    if (diff >= hrStrainedPct) return -2;
    if (diff >= hrStretchedPct) return -1;
    return 0;
  }

  int? _scoreTemp(PersonalBaseline baseline, SleepSession? lastNight) {
    final base = baseline.medianSkinTempCelsius;
    final last = lastNight?.avgSkinTempCelsius;
    if (base == null || last == null) return null;
    final delta = (last - base).abs();
    return delta > tempFlagDeltaC ? -1 : 0;
  }

  /// SECONDARY, DOWNWARD-ONLY: only ever returns 0 or -1, never +1 — a
  /// breathing rate well BELOW baseline is not a signal this engine
  /// reads as "better than usual", so there is nothing to reward.
  int? _scoreRespRate(PersonalBaseline baseline, SleepSession? lastNight) {
    final base = baseline.medianRespiratoryRateBrpm;
    final last = lastNight?.avgRespiratoryRateBrpm;
    if (base == null || last == null) return null;
    final delta = last - base; // positive = elevated
    return delta > respRateFlagDeltaBrpm ? -1 : 0;
  }

  /// 0-100, HIGHER = more stressed, DISPLAY ONLY (see the class-level
  /// comment on [stressHrvDepressionCeilingPct] for why this never
  /// feeds the recovery score). Prefers a vendor/health-source-provided
  /// [HealthSnapshot.stressIndex] when today has any; otherwise derives
  /// one from how far today's average HRV sits below the user's own
  /// baseline HRV. Null when neither is available.
  int? _deriveStress(
      PersonalBaseline baseline, List<HealthSnapshot> todaySnapshots) {
    final vendorReadings =
        todaySnapshots.map((s) => s.stressIndex).whereType<int>().toList();
    if (vendorReadings.isNotEmpty) {
      final avg = vendorReadings.reduce((a, b) => a + b) / vendorReadings.length;
      return avg.round().clamp(0, 100);
    }

    final baseHrv = baseline.medianHrvMs;
    if (baseHrv == null || baseHrv == 0) return null;
    final todayHrv =
        todaySnapshots.map((s) => s.hrvMs).whereType<int>().toList();
    if (todayHrv.isEmpty) return null;

    final avgHrv = todayHrv.reduce((a, b) => a + b) / todayHrv.length;
    final depression = (baseHrv - avgHrv) / baseHrv; // positive = below baseline
    final normalized =
        (depression / stressHrvDepressionCeilingPct).clamp(0.0, 1.0);
    return (normalized * 100).round();
  }

  /// Today's cumulative active-calorie total — the latest non-null
  /// [HealthSnapshot.activeEnergyKcal] (cumulative-since-midnight, same
  /// shape as `steps`), not a sum across snapshots. Null when today has
  /// no active-energy readings yet.
  int? _todayActiveEnergyKcal(List<HealthSnapshot> todaySnapshots) {
    for (final s in todaySnapshots.reversed) {
      if (s.activeEnergyKcal != null) return s.activeEnergyKcal;
    }
    return null;
  }

  /// The latest non-null [HealthSnapshot.heartRateBpm] among today's
  /// snapshots — same "latest reading, not an average" shape as
  /// [_todayActiveEnergyKcal]. Null when today has no HR readings yet.
  int? _todayHeartRateBpm(List<HealthSnapshot> todaySnapshots) {
    for (final s in todaySnapshots.reversed) {
      if (s.heartRateBpm != null) return s.heartRateBpm;
    }
    return null;
  }

  RecoveryState _stateFromTotal(int total) {
    if (total >= rechargedThreshold) return RecoveryState.recharged;
    if (total >= steadyThreshold) return RecoveryState.steady;
    if (total >= stretchedThreshold) return RecoveryState.stretched;
    return RecoveryState.rundown;
  }

  // ---- text composition: plain English, always tied to the user's own
  // baseline, never generic filler, never medical language. Actions
  // come from the Desi Plate content library (content/action_content.dart),
  // picked deterministically by date so the same day always reads the
  // same but consecutive days differ.

  _Composed _compose(
    RecoveryState state, {
    required DateTime date,
    required int? hrvScore,
    required int? sleepScore,
    required int? hrScore,
    required int? tempScore,
    required int? respRateScore,
    required SleepWording wording,
    required bool excludeDaytimeFood,
  }) {
    String headline;
    String meaning;

    // Which of HRV/sleep/HR is worst drives both the "why" sentence and
    // which action bucket to draw from. Only stretched/rundown ever
    // point at a specific signal — a good day has nothing to blame.
    final dominant =
        state == RecoveryState.stretched || state == RecoveryState.rundown
            ? _dominantNegativeSignal(hrvScore, sleepScore, hrScore)
            : DominantSignal.none;

    switch (state) {
      case RecoveryState.recharged:
        headline = 'Strong recovery today';
        meaning = 'Your HRV and sleep ${wording.lastSleepPeriod} were '
            'above your usual range, a sign your body recovered well.';
        break;
      case RecoveryState.steady:
        headline = 'Right in your normal range';
        meaning = "${wording.lastSleepPossessive} readings were close to "
            'your usual numbers, no strong signal either way.';
        break;
      case RecoveryState.stretched:
        headline = 'A bit stretched — ease up';
        meaning = _signalSentence(dominant, wording) ??
            'A couple of signals were mildly below your usual '
                '${wording.duringLastSleep}.';
        break;
      case RecoveryState.rundown:
        headline = 'Running low — prioritize recovery';
        meaning = _signalSentence(dominant, wording) ??
            'Several signals were well below your usual '
                '${wording.duringLastSleep}.';
        break;
      case RecoveryState.learning:
        // Handled before _compose is ever called.
        headline = '';
        meaning = '';
        break;
    }

    final actions = state == RecoveryState.learning
        ? <String>[]
        : ActionContent.pickActions(state, dominant, date,
            excludeDaytimeFood: excludeDaytimeFood);

    if (tempScore != null && tempScore < 0) {
      meaning += ' Your skin temperature was outside your usual range '
          '${wording.duringLastSleep} — your body is working harder '
          'than usual.';
      final tempActions = ActionContent.pickActions(
          state, DominantSignal.temp, date,
          count: 1, excludeDaytimeFood: excludeDaytimeFood);
      if (tempActions.isNotEmpty) {
        final tempAction = tempActions.first;
        if (actions.length >= 2) {
          actions[actions.length - 1] = tempAction;
        } else {
          actions.add(tempAction);
        }
      }
    }

    if (respRateScore != null && respRateScore < 0) {
      meaning += ' Your breathing rate ran higher than your usual '
          '${wording.duringLastSleep} — your body is working a little '
          'harder than usual.';
    }

    return _Composed(headline: headline, meaning: meaning, actions: actions);
  }

  /// Which of HRV/sleep/HR is most negative, in the user's own terms.
  /// Returns [DominantSignal.none] if none of the three are actually
  /// negative (e.g. the state was driven down by temperature alone).
  DominantSignal _dominantNegativeSignal(int? hrv, int? sleep, int? hr) {
    final entries = <MapEntry<DominantSignal, int>>[
      if (hrv != null) MapEntry(DominantSignal.hrv, hrv),
      if (sleep != null) MapEntry(DominantSignal.sleep, sleep),
      if (hr != null) MapEntry(DominantSignal.hr, hr),
    ];
    if (entries.isEmpty) return DominantSignal.none;
    entries.sort((a, b) => a.value.compareTo(b.value));
    final worst = entries.first;
    return worst.value < 0 ? worst.key : DominantSignal.none;
  }

  /// The "why" sentence for the dominant negative signal. Null for
  /// [DominantSignal.none]/[DominantSignal.temp] — temperature gets its
  /// own sentence appended separately, and "none" falls back to a
  /// generic multi-signal sentence at the call site.
  String? _signalSentence(DominantSignal signal, SleepWording wording) {
    switch (signal) {
      case DominantSignal.hrv:
        return 'Your HRV was well below your usual ${wording.duringLastSleep}, '
            'a sign your body is still catching up.';
      case DominantSignal.sleep:
        return 'You got noticeably less sleep than usual '
            '${wording.duringLastSleep}.';
      case DominantSignal.hr:
        return 'Your heart rate stayed higher than your usual '
            '${wording.duringLastSleep}, a sign of extra strain.';
      case DominantSignal.temp:
      case DominantSignal.none:
        return null;
    }
  }
}

class _Composed {
  final String headline;
  final String meaning;
  final List<String> actions;

  const _Composed({
    required this.headline,
    required this.meaning,
    required this.actions,
  });
}
