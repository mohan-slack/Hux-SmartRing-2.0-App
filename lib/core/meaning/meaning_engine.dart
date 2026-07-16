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
import 'daily_readout.dart';

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

  // ---- Signal weights (how much each moves the combined score) -------
  static const hrvWeight = 2;
  static const sleepWeight = 2;
  static const hrWeight = 1;
  static const tempWeight = 1;

  // ---- Combined-score cutoffs for the overall RecoveryState -----------
  static const rechargedThreshold = 3;
  static const steadyThreshold = 0;
  static const stretchedThreshold = -4;
  // Below stretchedThreshold => rundown.

  const MeaningEngine();

  /// Evaluate one day. [date] is passed in explicitly (not read from the
  /// system clock) so the engine stays a pure function of its inputs.
  DailyReadout evaluate({
    required DateTime date,
    required PersonalBaseline baseline,
    required SleepSession? lastNight,
    required List<HealthSnapshot> todaySnapshots,
  }) {
    if (baseline.insufficient) {
      return DailyReadout.learning(date, daysOfData: baseline.daysOfData);
    }

    final hrvScore = _scoreHrv(baseline, lastNight);
    final sleepScore = _scoreSleep(baseline, lastNight);
    final hrScore = _scoreRestingHr(baseline, lastNight);
    final tempScore = _scoreTemp(baseline, lastNight);

    final considered = [hrvScore, sleepScore, hrScore, tempScore]
        .where((s) => s != null)
        .length;

    if (considered == 0) {
      return DailyReadout.noSignal(date);
    }

    var total = 0;
    if (hrvScore != null) total += hrvScore * hrvWeight;
    if (sleepScore != null) total += sleepScore * sleepWeight;
    if (hrScore != null) total += hrScore * hrWeight;
    if (tempScore != null) total += tempScore * tempWeight;

    final state = _stateFromTotal(total);
    final quality = considered == 4
        ? DataQuality.full
        : (considered >= 2 ? DataQuality.partial : DataQuality.sparse);

    final composed =
        _compose(state, hrvScore: hrvScore, sleepScore: sleepScore,
            hrScore: hrScore, tempScore: tempScore);

    return DailyReadout(
      date: date,
      state: state,
      headline: composed.headline,
      meaning: composed.meaning,
      actions: composed.actions,
      dataQuality: quality,
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

  RecoveryState _stateFromTotal(int total) {
    if (total >= rechargedThreshold) return RecoveryState.recharged;
    if (total >= steadyThreshold) return RecoveryState.steady;
    if (total >= stretchedThreshold) return RecoveryState.stretched;
    return RecoveryState.rundown;
  }

  // ---- text composition: plain English, always tied to the user's own
  // baseline, never generic filler, never medical language ----

  _Composed _compose(
    RecoveryState state, {
    required int? hrvScore,
    required int? sleepScore,
    required int? hrScore,
    required int? tempScore,
  }) {
    String headline;
    String meaning;
    final actions = <String>[];

    switch (state) {
      case RecoveryState.recharged:
        headline = 'Recharged — strong recovery today';
        meaning = 'Your HRV and sleep last night were above your usual '
            'range, a sign your body recovered well.';
        actions.add('Good day to push a harder workout or a longer walk');
        actions.add('Use the extra energy on your most demanding task');
        break;
      case RecoveryState.steady:
        headline = 'Steady — right in your normal range';
        meaning = "Last night's readings were close to your usual "
            'numbers, no strong signal either way.';
        actions.add('Stick with your regular routine today');
        actions.add("Keep tonight's bedtime consistent with your usual");
        break;
      case RecoveryState.stretched:
        headline = 'A bit stretched today — ease up slightly';
        meaning = _worstSignalSentence(hrvScore, sleepScore, hrScore) ??
            'A couple of signals were mildly below your usual overnight.';
        actions.add(
            'Dial back workout intensity — a light walk over a hard session');
        actions.add('Aim for lights-out 30-45 minutes earlier tonight');
        break;
      case RecoveryState.rundown:
        headline = 'Running low today — prioritize recovery';
        meaning = _worstSignalSentence(hrvScore, sleepScore, hrScore) ??
            'Several signals were well below your usual overnight.';
        actions.add('Skip intense training today and prioritize rest');
        actions.add('Get to bed earlier and keep hydration up today');
        break;
      case RecoveryState.learning:
        // Handled before _compose is ever called.
        headline = '';
        meaning = '';
        break;
    }

    if (tempScore != null && tempScore < 0) {
      meaning += ' Your skin temperature was outside your usual range '
          'overnight — your body is working harder than usual.';
      const tempAction =
          'Prioritize rest today — your temperature was outside your '
          'usual range overnight';
      if (actions.length >= 2) {
        actions[actions.length - 1] = tempAction;
      } else {
        actions.add(tempAction);
      }
    }

    return _Composed(headline: headline, meaning: meaning, actions: actions);
  }

  /// Names the worst-scoring of the three named signals, in the user's
  /// own terms. Returns null if none of them are actually negative
  /// (e.g. the state was driven down by temperature alone).
  String? _worstSignalSentence(int? hrv, int? sleep, int? hr) {
    final entries = <MapEntry<String, int>>[
      if (hrv != null) MapEntry('hrv', hrv),
      if (sleep != null) MapEntry('sleep', sleep),
      if (hr != null) MapEntry('hr', hr),
    ];
    if (entries.isEmpty) return null;
    entries.sort((a, b) => a.value.compareTo(b.value));
    final worst = entries.first;
    if (worst.value >= 0) return null;

    switch (worst.key) {
      case 'hrv':
        return 'Your HRV was well below your usual last night, a sign '
            'your body is still catching up.';
      case 'sleep':
        return 'You slept noticeably less than your usual last night.';
      case 'hr':
        return 'Your heart rate stayed higher than your usual overnight, '
            'a sign of extra strain.';
    }
    return null;
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
