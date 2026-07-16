/// HUX Personal Baseline
/// ----------------------
/// The Meaning engine never compares a user to population norms — it
/// compares them to their OWN recent history. This file computes that
/// history into a single snapshot: [PersonalBaseline].
///
/// Medians (not means) are used throughout: a single rough night or a
/// missed reading must not drag the reference point around.

import '../ring/ring_models.dart';

/// The user's own recent-history reference point.
///
/// Built from the last [daysOfData] nights/days available (up to 14).
/// When [daysOfData] is below [PersonalBaseline.minDaysRequired], the
/// baseline is [insufficient] and the Meaning engine must not derive
/// insights from it.
class PersonalBaseline {
  /// Fewer nights than this and we don't know this body well enough yet.
  static const minDaysRequired = 3;

  final double? medianHrvMs;
  final double? medianRestingHeartRateBpm;
  final Duration? medianTotalSleep;
  final double? medianSkinTempCelsius;
  final int daysOfData;

  const PersonalBaseline({
    required this.medianHrvMs,
    required this.medianRestingHeartRateBpm,
    required this.medianTotalSleep,
    required this.medianSkinTempCelsius,
    required this.daysOfData,
  });

  bool get insufficient => daysOfData < minDaysRequired;

  /// Builds a baseline from up to the last 14 days of sleep sessions.
  /// Sessions with a null field simply don't contribute to that field's
  /// median — one missing HRV reading doesn't spoil the sleep-duration
  /// baseline, or vice versa.
  factory PersonalBaseline.fromSleepSessions(List<SleepSession> sessions) {
    final hrv = <double>[];
    final hr = <double>[];
    final sleepMinutes = <double>[];
    final temp = <double>[];

    for (final s in sessions) {
      if (s.avgHrvMs != null) hrv.add(s.avgHrvMs!.toDouble());
      if (s.avgHeartRateBpm != null) hr.add(s.avgHeartRateBpm!.toDouble());
      if (s.avgSkinTempCelsius != null) temp.add(s.avgSkinTempCelsius!);
      sleepMinutes.add(s.totalSleep.inMinutes.toDouble());
    }

    final medianSleepMinutes = _median(sleepMinutes);
    return PersonalBaseline(
      medianHrvMs: _median(hrv),
      medianRestingHeartRateBpm: _median(hr),
      medianTotalSleep: medianSleepMinutes == null
          ? null
          : Duration(minutes: medianSleepMinutes.round()),
      medianSkinTempCelsius: _median(temp),
      daysOfData: sessions.length,
    );
  }

  static double? _median(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
