/// HUX Weekly Body Story
/// ----------------------
/// Turns two weeks of history into a short, honest narrative: how this
/// week compares to the one before, in the user's own numbers — never
/// a population norm, same principle as the daily Meaning engine.
///
/// [WeeklyStory] is a pure data model. [WeeklyStoryService] is the only
/// thing here allowed to touch [HealthStore]; it loads both weeks,
/// computes medians, and hands off to plain, deterministic comparison
/// logic in this same file (kept together since there's no scoring
/// engine to separate out here, just arithmetic and sentences).
///
/// Wellness wording only — same medical-language ban as the rest of the
/// app. Vegetarian-first, Indian-context register where food comes up.

import '../modes/mode.dart';
import '../ring/ring_models.dart';
import '../storage/health_store.dart';

class WeeklyStory {
  final String title;

  /// 1-5 short sentences, each referencing the user's own week-over-week
  /// delta. Fewer of these — and more cautious wording — when either
  /// week is thin on data; see [thinData].
  final List<String> observations;

  /// Exactly one concrete suggestion for the coming week.
  final String suggestion;

  /// True when either week had fewer than
  /// [WeeklyStoryService.minNightsForFullConfidence] nights logged.
  /// The UI should treat this as informational, not alarming — thin
  /// data is normal early on or after a sync gap.
  final bool thinData;

  const WeeklyStory({
    required this.title,
    required this.observations,
    required this.suggestion,
    required this.thinData,
  });
}

class WeeklyStoryService {
  final HealthStore _store;

  /// Fewer nights than this in either week and the story says so
  /// honestly instead of drawing confident conclusions from thin data.
  static const minNightsForFullConfidence = 5;

  /// A day counts as "active" once cumulative steps cross this — a
  /// coarse, personal-context-free bar since v1 has no step baseline.
  static const activeStepsThreshold = 6000;

  /// Deltas smaller than these read as "about the same" rather than a
  /// direction — avoids reporting noise as a trend.
  static const _sleepDeadbandMinutes = 10;
  static const _hrvDeadbandMs = 3;
  static const _hrDeadbandBpm = 2;

  /// At least this many days of the week observing a fast and the story
  /// says so — a fasting week's numbers reflect the observance, not
  /// something to be concerned about.
  static const minFastDaysForNote = 3;

  WeeklyStoryService(this._store);

  Future<WeeklyStory> buildStory({DateTime? now}) async {
    final reference = (now ?? DateTime.now()).toUtc();
    final thisWeekStart = reference.subtract(const Duration(days: 7));
    final lastWeekStart = reference.subtract(const Duration(days: 14));

    final thisWeek =
        await _store.sleepSessionsBetween(thisWeekStart, reference);
    final lastWeek =
        await _store.sleepSessionsBetween(lastWeekStart, thisWeekStart);
    final thisSnapshots =
        await _store.snapshotsBetween(thisWeekStart, reference);
    final lastSnapshots =
        await _store.snapshotsBetween(lastWeekStart, thisWeekStart);

    final thinData = thisWeek.length < minNightsForFullConfidence ||
        lastWeek.length < minNightsForFullConfidence;

    final observations = <String>[];
    if (thinData) {
      observations.add(_coverageNote(thisWeek.length, lastWeek.length));
    }

    final sleepObs = _sleepObservation(thisWeek, lastWeek);
    final hrvObs = _hrvObservation(thisWeek, lastWeek);
    final hrObs = _hrObservation(thisWeek, lastWeek);
    final activeObs = _activeDaysObservation(thisSnapshots, lastSnapshots);

    // Thin data: stick to the single steadiest signal (sleep, since
    // it's present whenever a session is logged at all) rather than
    // stacking up claims a handful of nights can't really support.
    if (thinData) {
      if (sleepObs != null) observations.add(sleepObs);
    } else {
      for (final obs in [sleepObs, hrvObs, hrObs, activeObs]) {
        if (obs != null) observations.add(obs);
      }
    }

    final fastingObs = await _fastingObservation(thisWeekStart, reference);
    if (fastingObs != null) observations.add(fastingObs);

    return WeeklyStory(
      title: 'Your week, in plain words',
      observations: observations,
      suggestion: _suggestion(
        thinData: thinData,
        sleepDeltaMinutes: _sleepDeltaMinutes(thisWeek, lastWeek),
        hrvDeltaMs: _hrvDeltaMs(thisWeek, lastWeek),
        hrDeltaBpm: _hrDeltaBpm(thisWeek, lastWeek),
      ),
      thinData: thinData,
    );
  }

  // ---- medians --------------------------------------------------------

  static double? _median(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  double? _medianSleepMinutes(List<SleepSession> nights) =>
      _median([for (final n in nights) n.totalSleep.inMinutes.toDouble()]);

  double? _medianHrv(List<SleepSession> nights) => _median([
        for (final n in nights)
          if (n.avgHrvMs != null) n.avgHrvMs!.toDouble(),
      ]);

  double? _medianHr(List<SleepSession> nights) => _median([
        for (final n in nights)
          if (n.avgHeartRateBpm != null) n.avgHeartRateBpm!.toDouble(),
      ]);

  /// Active-day count for a week, or null if there are no snapshots at
  /// all (the metric genuinely doesn't exist for that week, distinct
  /// from "zero active days").
  int? _activeDays(List<HealthSnapshot> snapshots) {
    if (snapshots.isEmpty) return null;
    final maxStepsByDay = <DateTime, int>{};
    for (final s in snapshots) {
      if (s.steps == null) continue;
      final utc = s.timestamp.toUtc();
      final day = DateTime.utc(utc.year, utc.month, utc.day);
      final current = maxStepsByDay[day] ?? 0;
      if (s.steps! > current) maxStepsByDay[day] = s.steps!;
    }
    if (maxStepsByDay.isEmpty) return null;
    return maxStepsByDay.values
        .where((steps) => steps > activeStepsThreshold)
        .length;
  }

  // ---- deltas (null when either side is unavailable) -------------------

  int? _sleepDeltaMinutes(List<SleepSession> thisWeek, List<SleepSession> lastWeek) {
    final a = _medianSleepMinutes(thisWeek);
    final b = _medianSleepMinutes(lastWeek);
    if (a == null || b == null) return null;
    return (a - b).round();
  }

  int? _hrvDeltaMs(List<SleepSession> thisWeek, List<SleepSession> lastWeek) {
    final a = _medianHrv(thisWeek);
    final b = _medianHrv(lastWeek);
    if (a == null || b == null) return null;
    return (a - b).round();
  }

  int? _hrDeltaBpm(List<SleepSession> thisWeek, List<SleepSession> lastWeek) {
    final a = _medianHr(thisWeek);
    final b = _medianHr(lastWeek);
    if (a == null || b == null) return null;
    return (a - b).round();
  }

  // ---- observation sentences -------------------------------------------

  String? _sleepObservation(
      List<SleepSession> thisWeek, List<SleepSession> lastWeek) {
    final delta = _sleepDeltaMinutes(thisWeek, lastWeek);
    if (delta == null) return null;
    if (delta.abs() < _sleepDeadbandMinutes) {
      return 'Your sleep duration was about the same as last week.';
    }
    return delta > 0
        ? 'You averaged $delta minutes more sleep than last week.'
        : 'You averaged ${delta.abs()} minutes less sleep than last week.';
  }

  String? _hrvObservation(
      List<SleepSession> thisWeek, List<SleepSession> lastWeek) {
    final delta = _hrvDeltaMs(thisWeek, lastWeek);
    if (delta == null) return null;
    if (delta.abs() < _hrvDeadbandMs) {
      return 'Your HRV held steady compared to last week.';
    }
    return delta > 0
        ? 'Your HRV averaged about $delta ms higher than last week.'
        : 'Your HRV averaged about ${delta.abs()} ms lower than last week.';
  }

  String? _hrObservation(
      List<SleepSession> thisWeek, List<SleepSession> lastWeek) {
    final delta = _hrDeltaBpm(thisWeek, lastWeek);
    if (delta == null) return null;
    if (delta.abs() < _hrDeadbandBpm) {
      return 'Your overnight heart rate was about the same as last week.';
    }
    return delta < 0
        ? 'Your overnight heart rate ran ${delta.abs()} bpm lower than '
            'last week.'
        : 'Your overnight heart rate ran $delta bpm higher than last '
            'week.';
  }

  String? _activeDaysObservation(
      List<HealthSnapshot> thisWeek, List<HealthSnapshot> lastWeek) {
    final a = _activeDays(thisWeek);
    final b = _activeDays(lastWeek);
    if (a == null || b == null) return null;
    if (a == b) {
      return 'You had the same number of active days as last week ($a).';
    }
    return a > b
        ? 'You had ${a - b} more active day${a - b == 1 ? '' : 's'} than '
            'last week.'
        : 'You had ${b - a} fewer active day${b - a == 1 ? '' : 's'} than '
            'last week.';
  }

  /// When [minFastDaysForNote]+ days of THIS week fall inside the
  /// active Fasting Companion window, one neutral acknowledgement —
  /// null otherwise (no fast configured, or too few days of it this
  /// week to be the story). Only looks at the currently active fasting
  /// config, since past fasts aren't kept once ended, same as every
  /// other mode_state row.
  Future<String?> _fastingObservation(
      DateTime thisWeekStart, DateTime reference) async {
    final fasting = await _store.loadFastingState();
    if (fasting == null) return null;

    final fastDays = List.generate(
            7, (i) => thisWeekStart.add(Duration(days: i)))
        .where(fasting.isActiveOn)
        .length;
    if (fastDays < minFastDaysForNote) return null;

    return 'A fasting week (${fasting.type.displayName}) reads '
        'differently — your numbers reflect the observance, not a '
        'problem.';
  }

  String _coverageNote(int thisNights, int lastNights) {
    final thin = thisNights < lastNights ? thisNights : lastNights;
    return thin == 0
        ? "There's not enough logged yet to compare the two weeks — "
            'keep wearing your ring and check back.'
        : "You've only got a handful of nights logged in one of these "
            'weeks, so take this as a rough sketch rather than the full '
            'picture.';
  }

  // ---- the one suggestion ----------------------------------------------

  String _suggestion({
    required bool thinData,
    required int? sleepDeltaMinutes,
    required int? hrvDeltaMs,
    required int? hrDeltaBpm,
  }) {
    if (thinData) {
      return 'Wear your ring every night this week — a fuller week of '
          'data means a sharper story next time.';
    }

    // Point at whichever signal moved the wrong way the most, in the
    // user's own terms. Ties and all-improving weeks fall through to
    // an affirming, keep-it-up suggestion.
    final worsened = <MapEntry<String, int>>[
      if (sleepDeltaMinutes != null && sleepDeltaMinutes < -_sleepDeadbandMinutes)
        MapEntry('sleep', sleepDeltaMinutes.abs()),
      if (hrvDeltaMs != null && hrvDeltaMs < -_hrvDeadbandMs)
        MapEntry('hrv', hrvDeltaMs.abs()),
      if (hrDeltaBpm != null && hrDeltaBpm > _hrDeadbandBpm)
        MapEntry('hr', hrDeltaBpm.abs()),
    ];

    if (worsened.isEmpty) {
      return 'Whatever you did this week worked — keep the same sleep '
          'and meal timing going into next week.';
    }

    worsened.sort((a, b) => b.value.compareTo(a.value));
    switch (worsened.first.key) {
      case 'sleep':
        return 'Try shifting bedtime 20-30 minutes earlier a few nights '
            'this week and see if it moves the needle.';
      case 'hrv':
        return 'Add one slow, unhurried day this week — a short walk '
            'and an early night instead of a packed schedule.';
      case 'hr':
        return 'Ease off high-intensity workouts for a few days this '
            'week and lean on lighter meals in the evening.';
      default:
        return 'Keep an eye on your usual routine this week and see how '
            'the numbers move.';
    }
  }
}
