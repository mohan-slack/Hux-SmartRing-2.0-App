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

  const NightRow({
    required this.night,
    this.sleepDuration,
    this.avgHrvMs,
    this.avgHeartRateBpm,
    this.avgRespiratoryRateBrpm,
    this.avgStressIndex,
    this.activeEnergyKcal,
  });
}

/// One row per calendar day in `[from, to)`, keyed by each session's
/// bedtime date. A day with no matching session still gets a row —
/// with every field null.
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
}) {
  final byNight = <DateTime, SleepSession>{};
  for (final session in sessions) {
    final bedtime = session.bedtime.toUtc();
    final night = DateTime.utc(bedtime.year, bedtime.month, bedtime.day);
    byNight[night] = session;
  }

  final byDay = <DateTime, List<HealthSnapshot>>{};
  for (final snapshot in snapshots) {
    final ts = snapshot.timestamp.toUtc();
    final day = DateTime.utc(ts.year, ts.month, ts.day);
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

  final start = DateTime.utc(from.year, from.month, from.day);
  final end = DateTime.utc(to.year, to.month, to.day);

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
