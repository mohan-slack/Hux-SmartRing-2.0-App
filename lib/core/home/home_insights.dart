/// The small, glanceable facts the redesigned Home draws as shapes
/// instead of sentences: last week's sleep windows, resting heart rate
/// by night, today's steps by hour, and why today's Charge is what it
/// is (each signal against the user's own usual).
///
/// Pure: give it sessions and snapshots, get numbers back. No storage.
library;

import '../meaning/baseline.dart';
import '../ring/ring_models.dart';

/// One night's sleep window (local times).
class NightWindow {
  final DateTime bed;
  final DateTime wake;
  final int asleepMinutes;

  const NightWindow({required this.bed, required this.wake, required this.asleepMinutes});
}

enum WhyTone { good, neutral, watch }

/// One signal behind today's Charge, compared with the user's usual.
class WhyFactor {
  final String label;

  /// Short value: "−8%", "−40m", "+3 bpm", "usual".
  final String value;

  /// −1…1: how far from usual, for the bar (left = below usual).
  final double offset;
  final WhyTone tone;

  const WhyFactor({required this.label, required this.value, required this.offset, required this.tone});
}

class HomeInsights {
  /// Oldest first, 7 entries (null = no sleep that night).
  final List<NightWindow?> nights7;

  /// Night-average heart rate per night, oldest first, 7 entries.
  final List<int?> restingHr7;

  /// Steps taken in each hour from [firstHour], up to the current hour.
  final List<int> stepsByHour;

  /// Signals behind today's Charge (empty while learning).
  final List<WhyFactor> why;

  const HomeInsights({
    this.nights7 = const [],
    this.restingHr7 = const [],
    this.stepsByHour = const [],
    this.why = const [],
  });

  static const empty = HomeInsights();
  static const firstHour = 6;

  bool get hasWeek => nights7.whereType<NightWindow>().length >= 3;

  /// How many of the known nights started later than [target] + 15 min.
  int lateNights(DateTime target) {
    final t = target.hour * 60 + target.minute;
    var n = 0;
    for (final w in nights7.whereType<NightWindow>()) {
      if (_minutesAfter9pm(w.bed) > _minutesAfter9pm(DateTime(2000, 1, 1, t ~/ 60, t % 60)) + 15) n++;
    }
    return n;
  }

  /// Minutes since 9 PM, so 11:30 PM and 1:00 AM sort correctly.
  static int _minutesAfter9pm(DateTime t) => ((t.hour * 60 + t.minute) - 21 * 60 + 24 * 60) % (24 * 60);

  static HomeInsights compute({
    required List<SleepSession> sessions,
    required List<HealthSnapshot> todaySnapshots,
    required DateTime now,
  }) {
    final local = now.toLocal();
    final today = DateTime(local.year, local.month, local.day);

    // One main sleep per wake-up day.
    final main = PersonalBaseline.mainSleepPerDay(sessions);
    final byWakeDay = <DateTime, SleepSession>{};
    for (final s in main) {
      final w = s.wakeTime.toLocal();
      byWakeDay[DateTime(w.year, w.month, w.day)] = s;
    }
    final nights = <NightWindow?>[];
    final hr = <int?>[];
    for (var i = 6; i >= 0; i--) {
      final s = byWakeDay[today.subtract(Duration(days: i))];
      nights.add(s == null
          ? null
          : NightWindow(bed: s.bedtime.toLocal(), wake: s.wakeTime.toLocal(), asleepMinutes: s.totalSleep.inMinutes));
      hr.add(s?.avgHeartRateBpm);
    }

    // Steps per hour: cumulative-since-midnight readings → increments.
    final maxByHour = <int, int>{};
    for (final snap in todaySnapshots) {
      final st = snap.steps;
      if (st == null) continue;
      final h = snap.timestamp.toLocal().hour;
      if (st > (maxByHour[h] ?? -1)) maxByHour[h] = st;
    }
    final byHour = <int>[];
    var prev = 0;
    for (var h = 0; h <= local.hour; h++) {
      final cum = maxByHour[h];
      final inc = cum == null ? 0 : (cum - prev).clamp(0, 1 << 30);
      if (cum != null && cum > prev) prev = cum;
      if (h >= firstHour) byHour.add(inc);
    }

    // Why: last night vs the nights before it.
    final lastNight = byWakeDay[today];
    final why = <WhyFactor>[];
    if (lastNight != null) {
      final before = main.where((s) => s.bedtime.isBefore(lastNight.bedtime)).toList();
      final b = PersonalBaseline.fromSleepSessions(before.length > 14 ? before.sublist(before.length - 14) : before);
      if (!b.insufficient) {
        final hrv = lastNight.avgHrvMs;
        if (hrv != null && b.medianHrvMs != null && b.medianHrvMs! > 0) {
          final pct = (hrv - b.medianHrvMs!) / b.medianHrvMs! * 100;
          why.add(_factor('HRV', pct.abs() < 5 ? 'usual' : '${_sign(pct)}${pct.abs().round()}%', pct / 30,
              higherIsBetter: true, usual: pct.abs() < 5));
        }
        final usualSleep = b.medianTotalSleep?.inMinutes;
        if (usualSleep != null) {
          final d = lastNight.totalSleep.inMinutes - usualSleep;
          why.add(_factor('Sleep', d.abs() < 15 ? 'usual' : '${_sign(d.toDouble())}${_hm(d.abs())}', d / 120,
              higherIsBetter: true, usual: d.abs() < 15));
        }
        final rhr = lastNight.avgHeartRateBpm;
        if (rhr != null && b.medianRestingHeartRateBpm != null) {
          final d = rhr - b.medianRestingHeartRateBpm!;
          why.add(_factor('Resting HR', d.abs() < 2 ? 'usual' : '${_sign(d)}${d.abs().round()} bpm', d / 8,
              higherIsBetter: false, usual: d.abs() < 2));
        }
        final rr = lastNight.avgRespiratoryRateBrpm;
        if (rr != null && b.medianRespiratoryRateBrpm != null) {
          final d = rr - b.medianRespiratoryRateBrpm!;
          why.add(_factor('Breathing', d.abs() < 1 ? 'usual' : '${_sign(d)}${d.abs().toStringAsFixed(1)}/min', d / 3,
              higherIsBetter: false, usual: d.abs() < 1));
        }
      }
    }

    return HomeInsights(nights7: nights, restingHr7: hr, stepsByHour: byHour, why: why);
  }

  static String _sign(num v) => v < 0 ? '−' : '+';
  static String _hm(int m) => m >= 60 ? '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}' : '${m}m';

  static WhyFactor _factor(String label, String value, double offset,
      {required bool higherIsBetter, required bool usual}) {
    final o = offset.clamp(-1.0, 1.0);
    final better = higherIsBetter ? o > 0 : o < 0;
    return WhyFactor(
      label: label,
      value: value,
      offset: o,
      tone: usual ? WhyTone.neutral : (better ? WhyTone.good : WhyTone.watch),
    );
  }
}
