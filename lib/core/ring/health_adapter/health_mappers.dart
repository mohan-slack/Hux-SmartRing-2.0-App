/// HUX Health-Store Mappers
/// --------------------------
/// PURE DART. No Flutter, no platform channels, no I/O — every function
/// here is a deterministic transform from `health` package data points
/// (a plain Dart data model, not a live connection) to this app's own
/// `HealthSnapshot`/`SleepSession` contract. `HealthStoreRingAdapter` is
/// the only thing that calls the `health` plugin itself; everything in
/// this file is unit-testable with hand-built `HealthDataPoint`s.
///
/// HRV NOTE (wiki page 6): Apple Health reports HRV as SDNN; Health
/// Connect can report RMSSD. HUX rings use RMSSD. These are DIFFERENT
/// algorithms on different scales — this whole adapter exists to
/// exercise the PIPELINE (does a readout compute, does a night show up
/// in Trends), never to calibrate MeaningEngine's thresholds. Don't tune
/// hrvGoodPct/hrvStretchedPct/etc. against data synced through here.
///
/// STAGE-LESS SLEEP: some sources (older HealthKit entries, some
/// Health Connect writers) only report a generic "asleep" block with no
/// deep/light/REM breakdown. This code NEVER fabricates stages it
/// wasn't given — a stage-less night maps its whole block to `light`
/// and is flagged via [MappedSleepSession.hadRealStages] = false, so
/// the adapter can log it. Deep/REM will read as under-reported for
/// those nights — see the README caveat.

import 'package:health/health.dart' as hk;

import '../ring_models.dart';

/// Aligns [t] down to the nearest 10-minute boundary — matches the
/// ring's sampling cadence (a reading every ~10 minutes), so real
/// health-app data lands on the same grid the mock ring uses.
DateTime bucketStart(DateTime t) {
  final minute = (t.minute ~/ 10) * 10;
  return DateTime(t.year, t.month, t.day, t.hour, minute);
}

double? _numericValue(hk.HealthDataPoint point) {
  final value = point.value;
  return value is hk.NumericHealthValue ? value.numericValue.toDouble() : null;
}

/// Health platforms disagree on whether SpO2/blood-oxygen is reported
/// as a 0.0-1.0 fraction (HealthKit's native percent unit) or a 0-100
/// whole percentage (how Health Connect's `Percentage` type is
/// typically populated) — normalizing here means every downstream
/// consumer of a mapped snapshot can assume 0-100, same as the ring
/// model's own `spo2Percent` doc comment promises.
double _normalizeSpo2(double raw) => raw <= 1.0 ? raw * 100 : raw;

List<HealthSnapshot> _bucketNumeric(
  List<hk.HealthDataPoint> points,
  HealthSnapshot Function(DateTime bucket, double average) build,
) {
  final sums = <DateTime, double>{};
  final counts = <DateTime, int>{};
  for (final point in points) {
    final value = _numericValue(point);
    if (value == null) continue;
    final bucket = bucketStart(point.dateFrom);
    sums[bucket] = (sums[bucket] ?? 0) + value;
    counts[bucket] = (counts[bucket] ?? 0) + 1;
  }

  final result = [
    for (final bucket in sums.keys) build(bucket, sums[bucket]! / counts[bucket]!),
  ];
  result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return result;
}

/// Buckets heart-rate points onto the 10-minute grid, averaging
/// multiple readings that land in the same bucket. Every other field
/// on the resulting snapshots is null — combine with the other mapXxx
/// outputs via [mergeSnapshots] to get full multi-metric snapshots,
/// same shape [MockRingAdapter] produces.
List<HealthSnapshot> mapHrSamples(List<hk.HealthDataPoint> points) =>
    _bucketNumeric(points,
        (bucket, avg) => HealthSnapshot(timestamp: bucket, heartRateBpm: avg.round()));

/// See the file-level HRV NOTE: values here may be SDNN (Apple) or
/// RMSSD (Health Connect/ring), depending entirely on which source the
/// data came from. Never compared against MeaningEngine's RMSSD-tuned
/// thresholds with any real confidence.
List<HealthSnapshot> mapHrvSamples(List<hk.HealthDataPoint> points) =>
    _bucketNumeric(
        points, (bucket, avg) => HealthSnapshot(timestamp: bucket, hrvMs: avg.round()));

List<HealthSnapshot> mapSpo2(List<hk.HealthDataPoint> points) => _bucketNumeric(
      points,
      (bucket, avg) =>
          HealthSnapshot(timestamp: bucket, spo2Percent: _normalizeSpo2(avg).round()),
    );

List<HealthSnapshot> mapBodyTemp(List<hk.HealthDataPoint> points) => _bucketNumeric(
      points,
      (bucket, avg) => HealthSnapshot(
          timestamp: bucket, skinTempCelsius: double.parse(avg.toStringAsFixed(2))),
    );

/// Unlike HR/HRV/SpO2 (point-in-time readings), the ring model's
/// `steps` is CUMULATIVE SINCE MIDNIGHT, ring-local (see
/// ring_models.dart) — not the raw per-interval count HealthKit/Health
/// Connect report. This buckets onto the 10-minute grid per calendar
/// day (so cumulative totals reset at each day boundary) THEN runs a
/// cumulative sum across that day's buckets in order.
List<HealthSnapshot> mapSteps(List<hk.HealthDataPoint> points) {
  final byDay = <DateTime, Map<DateTime, double>>{};
  for (final point in points) {
    final value = _numericValue(point);
    if (value == null) continue;
    final day = DateTime(point.dateFrom.year, point.dateFrom.month, point.dateFrom.day);
    final bucket = bucketStart(point.dateFrom);
    final buckets = byDay.putIfAbsent(day, () => {});
    buckets[bucket] = (buckets[bucket] ?? 0) + value;
  }

  final result = <HealthSnapshot>[];
  for (final buckets in byDay.values) {
    final sortedBuckets = buckets.keys.toList()..sort();
    var running = 0.0;
    for (final bucket in sortedBuckets) {
      running += buckets[bucket]!;
      result.add(HealthSnapshot(timestamp: bucket, steps: running.round()));
    }
  }
  result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return result;
}

/// Combines the separate per-metric snapshot lists (each produced by
/// exactly one of the mapXxx functions above, each with only ITS OWN
/// field populated) into one snapshot per 10-minute bucket with every
/// available metric filled in — mirroring how [MockRingAdapter] emits
/// one multi-metric snapshot per reading rather than parallel streams.
/// Where two lists both have a value for the same bucket, the FIRST
/// list in [perMetricLists] wins for that field (in practice each
/// field only ever comes from one list, so this never actually
/// contends — the precedence rule just keeps behavior well-defined).
List<HealthSnapshot> mergeSnapshots(List<List<HealthSnapshot>> perMetricLists) {
  final byBucket = <DateTime, HealthSnapshot>{};
  for (final list in perMetricLists) {
    for (final snap in list) {
      final existing = byBucket[snap.timestamp];
      byBucket[snap.timestamp] = existing == null
          ? snap
          : HealthSnapshot(
              timestamp: snap.timestamp,
              heartRateBpm: existing.heartRateBpm ?? snap.heartRateBpm,
              hrvMs: existing.hrvMs ?? snap.hrvMs,
              spo2Percent: existing.spo2Percent ?? snap.spo2Percent,
              skinTempCelsius: existing.skinTempCelsius ?? snap.skinTempCelsius,
              steps: existing.steps ?? snap.steps,
            );
    }
  }
  final result = byBucket.values.toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return result;
}

/// The sleep-stage data types this adapter understands, and their
/// mapping onto [SleepStage] — deep->deep, rem->rem, core/light->light,
/// awake->awake. Two sources are STAGE-LESS (see the file-level
/// STAGE-LESS SLEEP note) and both fold into `light`:
/// - SLEEP_ASLEEP: the generic/unspecified "asleep" block some sources
///   report instead of a stage breakdown.
/// - SLEEP_IN_BED: what HealthKit's own Health app writes for a plain
///   manually-entered sleep span (`HKCategoryValueSleepAnalysis.inBed`)
///   — there's no "asleep" signal at all here, only "in bed", but
///   treating it as stage-less sleep rather than discarding it is what
///   makes the simulator's manual-Health-data trick (see README) work;
///   a real device synced via a sleep-tracking app/Watch reports proper
///   asleep/stage data instead.
/// Any OTHER sleep-related type (SLEEP_SESSION, SLEEP_UNKNOWN, ...)
/// isn't a stage on its own and is ignored for segment purposes.
SleepStage? _stageFor(hk.HealthDataType type) => switch (type) {
      hk.HealthDataType.SLEEP_DEEP => SleepStage.deep,
      hk.HealthDataType.SLEEP_REM => SleepStage.rem,
      hk.HealthDataType.SLEEP_LIGHT => SleepStage.light,
      hk.HealthDataType.SLEEP_AWAKE => SleepStage.awake,
      hk.HealthDataType.SLEEP_ASLEEP => SleepStage.light,
      hk.HealthDataType.SLEEP_IN_BED => SleepStage.light,
      _ => null,
    };

/// The stage-less source types — see [_stageFor]'s doc comment.
const _stagelessTypes = {
  hk.HealthDataType.SLEEP_ASLEEP,
  hk.HealthDataType.SLEEP_IN_BED,
};

/// A gap this long or longer between two consecutive sleep-stage
/// points splits them into separate sessions (separate nights) rather
/// than one — bigger than any real in-night awakening, small enough
/// that two genuinely different nights never get merged into one.
const sleepSessionGapThreshold = Duration(hours: 2);

/// One mapped night, plus whether it came from a source with real
/// stage detail. See the file-level STAGE-LESS SLEEP note.
class MappedSleepSession {
  final SleepSession session;
  final bool hadRealStages;

  const MappedSleepSession({required this.session, required this.hadRealStages});
}

/// Groups sleep-stage points into distinct nights (splitting on gaps
/// >= [sleepSessionGapThreshold]) and builds a [SleepSession] for each,
/// including averages computed from whichever HR/HRV/SpO2/temperature
/// points fall inside that night's [bedtime, wakeTime) window. Handles
/// a night spanning midnight the same as any other — sessions are
/// built from elapsed time between points, never calendar-day
/// boundaries.
List<MappedSleepSession> mapSleepSessions(
  List<hk.HealthDataPoint> sleepPoints, {
  List<hk.HealthDataPoint> hrPoints = const [],
  List<hk.HealthDataPoint> hrvPoints = const [],
  List<hk.HealthDataPoint> spo2Points = const [],
  List<hk.HealthDataPoint> tempPoints = const [],
}) {
  final relevant = sleepPoints.where((p) => _stageFor(p.type) != null).toList()
    ..sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
  if (relevant.isEmpty) return const [];

  final clusters = <List<hk.HealthDataPoint>>[];
  var current = <hk.HealthDataPoint>[relevant.first];
  for (final point in relevant.skip(1)) {
    final gap = point.dateFrom.difference(current.last.dateTo);
    if (gap >= sleepSessionGapThreshold) {
      clusters.add(current);
      current = [point];
    } else {
      current.add(point);
    }
  }
  clusters.add(current);

  return [
    for (final cluster in clusters)
      _buildSession(cluster, hrPoints, hrvPoints, spo2Points, tempPoints),
  ];
}

MappedSleepSession _buildSession(
  List<hk.HealthDataPoint> cluster,
  List<hk.HealthDataPoint> hrPoints,
  List<hk.HealthDataPoint> hrvPoints,
  List<hk.HealthDataPoint> spo2Points,
  List<hk.HealthDataPoint> tempPoints,
) {
  final hadRealStages = cluster.any((p) => !_stagelessTypes.contains(p.type));

  final segments = [
    for (final p in cluster)
      SleepSegment(start: p.dateFrom, end: p.dateTo, stage: _stageFor(p.type)!),
  ]..sort((a, b) => a.start.compareTo(b.start));

  final bedtime = segments.first.start;
  final wakeTime = segments.last.end;

  List<double> valuesInWindow(List<hk.HealthDataPoint> points) => points
      .where((p) => !p.dateFrom.isBefore(bedtime) && p.dateFrom.isBefore(wakeTime))
      .map(_numericValue)
      .whereType<double>()
      .toList();

  int? avgInt(List<hk.HealthDataPoint> points) {
    final values = valuesInWindow(points);
    if (values.isEmpty) return null;
    return (values.reduce((a, b) => a + b) / values.length).round();
  }

  final spo2Values = valuesInWindow(spo2Points).map(_normalizeSpo2).toList();
  final minSpo2 = spo2Values.isEmpty
      ? null
      : spo2Values.reduce((a, b) => a < b ? a : b).round();

  final tempValues = valuesInWindow(tempPoints);
  final avgTemp = tempValues.isEmpty
      ? null
      : double.parse(
          (tempValues.reduce((a, b) => a + b) / tempValues.length).toStringAsFixed(2));

  return MappedSleepSession(
    session: SleepSession(
      bedtime: bedtime,
      wakeTime: wakeTime,
      segments: segments,
      avgHeartRateBpm: avgInt(hrPoints),
      avgHrvMs: avgInt(hrvPoints),
      minSpo2Percent: minSpo2,
      avgSkinTempCelsius: avgTemp,
    ),
    hadRealStages: hadRealStages,
  );
}
