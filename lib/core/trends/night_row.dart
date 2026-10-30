/// HUX Trends — per-night rows
/// -----------------------------
/// Pure Dart. Turns raw [SleepSession]s into one row per calendar
/// night, including nights with no session at all. That's the whole
/// point: a night HUX never synced must render as a gap in the
/// Trends charts, never as a zero — a zero would read as "you didn't
/// sleep," which is a claim we have no data for.
///
/// No Flutter imports here; `trends_screen.dart` is the only consumer
/// and does the actual charting.

import '../meaning/baseline.dart';
import '../ring/ring_models.dart';

/// One calendar night's trend data. Null fields mean "no reading" —
/// either the whole night is missing (no session synced) or the ring
/// simply didn't compute that particular metric.
class NightRow {
  final DateTime night;
  final Duration? sleepDuration;
  final double? avgHrvMs;
  final double? avgHeartRateBpm;

  /// From that night's [SleepSession.avgRespiratoryRateBrpm] — an
  /// overnight-recovery input, same family as the two averages above.
  final double? avgRespiratoryRateBrpm;

  /// Average of that CALENDAR DAY's [HealthSnapshot.stressIndex]
  /// readings — a daytime figure, keyed by [night]'s date rather than
  /// derived from the sleep session itself.
  final double? avgStressIndex;

  /// That calendar day's cumulative active-calorie total — the highest
  /// [HealthSnapshot.activeEnergyKcal] reading (cumulative-since-
  /// midnight, same shape as steps), not a sum across snapshots.
  final double? activeEnergyKcal;

  /// That calendar day's step total — the highest cumulative
  /// [HealthSnapshot.steps] reading, like [activeEnergyKcal].
  final double? steps;

  const NightRow({
    required this.night,
    this.sleepDuration,
    this.avgHrvMs,
    this.avgHeartRateBpm,
    this.avgRespiratoryRateBrpm,
    this.avgStressIndex,
    this.activeEnergyKcal,
    this.steps,
  });
}

/// One row per calendar day in `[from, to)`, keyed by each session's
/// bedtime date. A day with no matching session still gets a row —
/// with every field null.
///
/// Days are the user's LOCAL calendar days (an IST user's 00:00–05:30
/// must not land on the previous UTC day). [utcOffset] overrides the
/// device's own offset — tests pin it so they pass in any timezone.
/// Row keys stay `DateTime.utc(y, m, d)` purely as date labels.
///
/// A bedtime before [nightCutoffHour] (06:00 local) belongs to the
/// PREVIOUS night: falling asleep at 00:30 is still "Monday night".
/// When two sessions share a night (a nap), the longest one wins.
///
/// If [to] is part-way through a day (e.g. "now"), that day is included,
/// so today's row is never dropped.
///
/// [snapshots] is optional (defaults to none, matching every pre-
/// existing caller) — when supplied, each row's daytime fields
/// ([NightRow.avgStressIndex], [NightRow.activeEnergyKcal]) are
/// aggregated from whichever snapshots fall on that row's calendar
/// day, independent of the sleep-session lookup above.
List<NightRow> buildNightRows({
  required DateTime from,
  required DateTime to,
  required List<SleepSession> sessions,
  List<HealthSnapshot> snapshots = const [],
  Duration? utcOffset,
}) {
  final byNight = <DateTime, SleepSession>{};
  for (final session in sessions) {
    final shifted = _toLocalWallClock(session.bedtime, utcOffset)
        .subtract(const Duration(hours: nightCutoffHour));
    final night = _dateKey(shifted);
    final existing = byNight[night];
    if (existing == null || session.totalSleep > existing.totalSleep) {
      byNight[night] = session;
    }
  }

  final byDay = <DateTime, List<HealthSnapshot>>{};
  for (final snapshot in snapshots) {
    final day = _dateKey(_toLocalWallClock(snapshot.timestamp, utcOffset));
    byDay.putIfAbsent(day, () => []).add(snapshot);
  }

  double? averageOf(
      List<HealthSnapshot> daySnapshots, int? Function(HealthSnapshot) valueOf) {
    final values = daySnapshots.map(valueOf).whereType<int>().toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double? maxOf(
      List<HealthSnapshot> daySnapshots, int? Function(HealthSnapshot) valueOf) {
    final values = daySnapshots.map(valueOf).whereType<int>().toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a > b ? a : b).toDouble();
  }

  final start = _dateKey(_toLocalWallClock(from, utcOffset));
  final toLocal = _toLocalWallClock(to, utcOffset);
  final toDay = _dateKey(toLocal);
  final toIsMidnight = toLocal.hour == 0 &&
      toLocal.minute == 0 &&
      toLocal.second == 0 &&
      toLocal.millisecond == 0 &&
      toLocal.microsecond == 0;
  final end = toIsMidnight ? toDay : toDay.add(const Duration(days: 1));

  final rows = <NightRow>[];
  for (var day = start; day.isBefore(end); day = day.add(const Duration(days: 1))) {
    final session = byNight[day];
    final daySnapshots = byDay[day] ?? const [];
    rows.add(NightRow(
      night: day,
      sleepDuration: session?.totalSleep,
      avgHrvMs: session?.avgHrvMs?.toDouble(),
      avgHeartRateBpm: session?.avgHeartRateBpm?.toDouble(),
      avgRespiratoryRateBrpm: session?.avgRespiratoryRateBrpm,
      avgStressIndex: averageOf(daySnapshots, (s) => s.stressIndex),
      activeEnergyKcal: maxOf(daySnapshots, (s) => s.activeEnergyKcal),
      steps: maxOf(daySnapshots, (s) => s.steps),
    ));
  }
  return rows;
}

/// A personal — never population — target range for the sleep-duration
/// chart: the user's own baseline median, ±10%.
class SleepTargetBand {
  final Duration low;
  final Duration high;

  const SleepTargetBand({required this.low, required this.high});

  /// Null when the baseline doesn't have a median sleep duration yet
  /// (not enough history) — the chart should simply omit the band.
  static SleepTargetBand? fromBaseline(PersonalBaseline baseline,
      {double tolerance = 0.10}) {
    final median = baseline.medianTotalSleep;
    if (median == null) return null;
    final minutes = median.inMinutes;
    return SleepTargetBand(
      low: Duration(minutes: (minutes * (1 - tolerance)).round()),
      high: Duration(minutes: (minutes * (1 + tolerance)).round()),
    );
  }
}

/// Splits a per-night series into contiguous runs of non-null values,
/// each a list of (index, value) pairs. A line chart renders each run
/// as its own segment so a gap between runs is a true visual break —
/// never a line interpolated straight across missing nights.
List<List<MapEntry<int, double>>> contiguousRuns(List<double?> values) {
  final runs = <List<MapEntry<int, double>>>[];
  List<MapEntry<int, double>>? current;

  for (var i = 0; i < values.length; i++) {
    final value = values[i];
    if (value == null) {
      current = null;
      continue;
    }
    if (current == null) {
      current = [];
      runs.add(current);
    }
    current.add(MapEntry(i, value));
  }
  return runs;
}

/// A bedtime earlier than this local hour counts toward the previous
/// night (see [buildNightRows]).
const nightCutoffHour = 6;

/// [t] as local wall-clock fields: the device's zone, or UTC + [offset].
/// The result is only read for its fields (year..microsecond), never
/// compared as an instant.
DateTime _toLocalWallClock(DateTime t, Duration? offset) =>
    offset == null ? t.toLocal() : t.toUtc().add(offset);

DateTime _dateKey(DateTime wallClock) =>
    DateTime.utc(wallClock.year, wallClock.month, wallClock.day);

/// Which night (as a `DateTime.utc(y, m, d)` date label) a sleep with
/// this [bedtime] belongs to — same rule as [buildNightRows]: local
/// calendar day, and a bedtime before [nightCutoffHour] counts as the
/// previous night. Shared so the journal matches "Monday's chai" to
/// "Monday night" exactly the way Trends does.
DateTime nightKeyFor(DateTime bedtime, {Duration? utcOffset}) => _dateKey(
    _toLocalWallClock(bedtime, utcOffset)
        .subtract(const Duration(hours: nightCutoffHour)));

/// The local calendar day of [t] as a `DateTime.utc(y, m, d)` label.
DateTime localDayKey(DateTime t, {Duration? utcOffset}) =>
    _dateKey(_toLocalWallClock(t, utcOffset));
