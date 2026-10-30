/// Cycle predictions — pure functions, no storage.
///
/// Honest by design:
/// - The next period is a RANGE ("likely 12–15 Nov") with a confidence
///   that grows with each logged cycle, never a single promised day.
/// - Irregular / perimenopause modes widen the range instead of guessing.
/// - Phases are estimates (ovulation ≈ 14 days before the next period).
///   NOT for contraception or fertility planning.
library;

import 'dart:math' as math;

import 'cycle_models.dart';

enum Confidence { none, low, medium, high }

extension ConfidenceX on Confidence {
  String get label => switch (this) {
        Confidence.none => 'not enough data',
        Confidence.low => 'low confidence',
        Confidence.medium => 'medium confidence',
        Confidence.high => 'high confidence',
      };
}

class CycleForecast {
  final CycleMode mode;
  final DateTime today;
  final DateTime? lastStart;

  /// 1-based day of the current cycle (null = no period logged yet).
  final int? dayOfCycle;
  final CyclePhase? phase;

  /// A period is logged as started and not yet ended (≤ 10 days).
  final bool periodOpen;
  final int avgCycleDays;
  final int periodDays;
  final DateTime? likely;
  final DateTime? from;
  final DateTime? to;
  final Confidence confidence;

  /// Today is past the end of the predicted range.
  final bool isLate;
  final int cyclesUsed;
  final List<String> notes;

  const CycleForecast({
    required this.mode,
    required this.today,
    this.lastStart,
    this.dayOfCycle,
    this.phase,
    this.periodOpen = false,
    required this.avgCycleDays,
    required this.periodDays,
    this.likely,
    this.from,
    this.to,
    this.confidence = Confidence.none,
    this.isLate = false,
    this.cyclesUsed = 0,
    this.notes = const [],
  });

  /// Days from today until the range opens (negative = already inside).
  int? get daysToWindow => from == null ? null : daysBetween(today, from!);

  /// Show the "Period started" button: inside / just before the window,
  /// or late. Always available on the Cycle screen itself.
  bool get nearWindow {
    if (periodOpen) return false;
    if (isLate) return true;
    final d = daysToWindow;
    return d != null && d <= 3 && !today.isAfter(to!);
  }
}

class CyclePredictor {
  const CyclePredictor._();

  /// Cycles shorter/longer than this are treated as logging gaps.
  static const minCycle = 15;
  static const maxCycle = 90;

  /// A period with no end logged is treated as over after this many days.
  static const autoCloseDays = 10;

  /// Cycle lengths between consecutive starts (plausible ones only).
  static List<int> cycleLengths(List<PeriodRecord> periods) {
    final out = <int>[];
    for (var i = 1; i < periods.length; i++) {
      final d = daysBetween(periods[i - 1].start, periods[i].start);
      if (d >= minCycle && d <= maxCycle) out.add(d);
    }
    return out;
  }

  static double? _sd(List<int> v) {
    if (v.length < 2) return null;
    final mean = v.reduce((a, b) => a + b) / v.length;
    final variance = v.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / (v.length - 1);
    return math.sqrt(variance);
  }

  /// Phase for 1-based [day] in a cycle of [cycleLength] whose period
  /// lasts [periodLength] days. Ovulation ≈ [cycleLength] − 14.
  static CyclePhase phaseForDay(int day, int cycleLength, int periodLength) {
    if (day <= periodLength) return CyclePhase.period;
    final ov = math.max(periodLength + 2, cycleLength - 14);
    if (day >= ov - 1 && day <= ov + 1) return CyclePhase.ovulatory;
    if (day > ov + 1) return CyclePhase.luteal;
    return CyclePhase.follicular;
  }

  static int _avg(CycleData data) {
    final recent = cycleLengths(data.periods);
    final last = recent.length > 6 ? recent.sublist(recent.length - 6) : recent;
    if (last.isEmpty) return data.settings.usualCycleDays;
    // Recent cycles count more (weights 1..n).
    var sum = 0.0, w = 0.0;
    for (var i = 0; i < last.length; i++) {
      sum += last[i] * (i + 1);
      w += i + 1;
    }
    return (sum / w).round();
  }

  static int _periodDays(CycleData data) {
    final closed = data.periods.map((p) => p.lengthDays).whereType<int>().where((l) => l >= 2 && l <= 10).toList();
    final last = closed.length > 6 ? closed.sublist(closed.length - 6) : closed;
    if (last.isEmpty) return data.settings.usualPeriodDays;
    final s = [...last]..sort();
    return s[s.length ~/ 2];
  }

  static CycleForecast forecast(CycleData data, DateTime now) {
    final today = dayOf(now);
    final mode = data.settings.mode;
    final avg = _avg(data);
    final pDays = _periodDays(data);
    final periods = data.periods.where((p) => !p.start.isAfter(today)).toList();
    if (periods.isEmpty) {
      return CycleForecast(mode: mode, today: today, avgCycleDays: avg, periodDays: pDays);
    }

    final last = periods.last;
    final day = daysBetween(last.start, today) + 1;
    final open = last.end == null && day <= autoCloseDays;

    final all = cycleLengths(data.periods);
    final recent = all.length > 6 ? all.sublist(all.length - 6) : all;
    final sd = _sd(recent);

    var half = recent.length < 2 ? 3 : (sd!.round() + 1).clamp(1, 7).toInt();
    if (mode.wide) half = math.max(half, 5);

    var conf = recent.isEmpty
        ? Confidence.low
        : (recent.length < 3 || (sd ?? 99) > 4)
            ? Confidence.low
            : (recent.length >= 6 && sd! <= 2)
                ? Confidence.high
                : Confidence.medium;
    if (mode.wide && conf == Confidence.high) conf = Confidence.medium;

    DateTime? likely, from, to;
    var isLate = false;
    if (mode.predicts) {
      likely = addDays(last.start, avg);
      from = addDays(likely, -half);
      to = addDays(likely, half);
      isLate = !open && today.isAfter(to);
    } else {
      conf = Confidence.none;
    }

    CyclePhase? phase;
    if (mode.hasPhases && !isLate && day <= avg + 7) {
      final thisPeriod = open ? day : (last.lengthDays ?? pDays);
      phase = open ? CyclePhase.period : phaseForDay(day, avg, thisPeriod);
    } else if (open) {
      phase = CyclePhase.period;
    }

    return CycleForecast(
      mode: mode,
      today: today,
      lastStart: last.start,
      dayOfCycle: day,
      phase: phase,
      periodOpen: open,
      avgCycleDays: avg,
      periodDays: pDays,
      likely: likely,
      from: from,
      to: to,
      confidence: conf,
      isLate: isLate,
      cyclesUsed: recent.length,
      notes: patternNotes(data, today),
    );
  }

  /// Gentle, informational notes. Never a diagnosis, never red.
  static List<String> patternNotes(CycleData data, DateTime today) {
    final mode = data.settings.mode;
    if (mode == CycleMode.pregnant || mode == CycleMode.hormonal) return const [];
    final notes = <String>[];
    final lengths = cycleLengths(data.periods);
    final last3 = lengths.length >= 3 ? lengths.sublist(lengths.length - 3) : const <int>[];
    if (last3.isNotEmpty && last3.every((l) => l > 35)) {
      notes.add('Your last 3 cycles were longer than 35 days. Worth mentioning to a doctor at your next visit — '
          'it is common and usually simple to check.');
    } else if (last3.isNotEmpty && last3.every((l) => l < 21)) {
      notes.add('Your last 3 cycles were shorter than 21 days. Worth mentioning to a doctor at your next visit.');
    }
    final recentClosed = data.periods.where((p) => p.end != null).toList();
    final tail = recentClosed.length > 3 ? recentClosed.sublist(recentClosed.length - 3) : recentClosed;
    if (tail.any((p) => p.lengthDays! > 8)) {
      notes.add('A recent period lasted more than 8 days. Worth mentioning to a doctor.');
    }
    if (data.periods.isNotEmpty) {
      final since = daysBetween(data.periods.last.start, today);
      if (since > 90) {
        notes.add('No period logged for over 90 days. If that is unexpected, check in with a doctor.');
      }
    }
    if (mode == CycleMode.regular && lengths.length >= 4) {
      final l6 = lengths.length > 6 ? lengths.sublist(lengths.length - 6) : lengths;
      if (l6.reduce(math.max) - l6.reduce(math.min) > 9) {
        notes.add('Your cycle length varies quite a bit. Irregular mode gives wider, calmer predictions.');
      }
    }
    return notes;
  }
}

/// Looks up the (estimated) phase of any past day — used to compare
/// scores with the user's own same-phase days.
class CyclePhaseResolver {
  final CycleData data;
  final int avgCycleDays;
  final int periodDays;

  CyclePhaseResolver(this.data)
      : avgCycleDays = CyclePredictor._avg(data),
        periodDays = CyclePredictor._periodDays(data);

  CyclePhase? phaseOn(DateTime when) {
    final day = dayOf(when);
    final ps = data.periods;
    var i = -1;
    for (var k = 0; k < ps.length; k++) {
      if (!ps[k].start.isAfter(day)) i = k;
    }
    if (i < 0) return null;
    final p = ps[i];
    final next = i + 1 < ps.length ? ps[i + 1] : null;
    final d = daysBetween(p.start, day) + 1;
    var len = avgCycleDays;
    if (next != null) {
      final gap = daysBetween(p.start, next.start);
      if (gap < CyclePredictor.minCycle || gap > CyclePredictor.maxCycle) return null;
      len = gap;
    } else if (d > avgCycleDays + 7) {
      return null;
    }
    return CyclePredictor.phaseForDay(d, len, p.lengthDays ?? periodDays);
  }
}
