/// HUX Charge
/// ----------
/// One 1–100 number for "how much energy do I have right now", shown to
/// every user at the top of Today. (Our own name — "Body Battery" is a
/// Garmin trademark.)
///
/// How it works, in plain words:
/// 1. MORNING CHARGE — last night's recovery vs the user's OWN baseline.
///    A night exactly at your usual reads as [usualNightCharge] (70),
///    better nights rise toward 100, harder nights fall toward 0.
/// 2. DAYTIME DRAIN — from the morning charge, energy drains with time
///    awake, active calories and daytime stress.
///
/// PURE DART, deterministic, no I/O: everything is passed in. Wellness
/// wording only — it describes energy, never health conditions.
library;

import '../ring/ring_models.dart';
import 'baseline.dart';

enum ChargeLevel { full, good, low, veryLow }

class HuxCharge {
  /// Right now, 1–100. Null while learning or without last night's data.
  final int? value;

  /// What the night gave you, before any daytime drain. Null as [value].
  final int? morningCharge;

  /// Null when [value] is null.
  final ChargeLevel? level;

  /// Short label for the ring ("Good to go"), or why there's no number.
  final String label;

  /// The biggest reason behind today's number, in plain words. Null when
  /// there's nothing to explain.
  final String? reason;

  const HuxCharge({
    required this.value,
    required this.morningCharge,
    required this.level,
    required this.label,
    this.reason,
  });

  bool get hasValue => value != null;
}

class HuxChargeCalculator {
  /// A night exactly at the user's usual reads as this.
  static const usualNightCharge = 70.0;

  // How far from usual counts as "much better/worse" for each signal
  // (that distance moves the component by 30 points: 70 -> 100 or 40).
  static const hrvSpanPct = 0.25;
  static const sleepSpanPct = 0.30;
  static const restingHrSpanPct = 0.15;

  // Weights of the overnight signals (re-normalised over what's present).
  static const hrvWeight = 0.4;
  static const sleepWeight = 0.4;
  static const restingHrWeight = 0.2;

  // Daytime drain.
  /// Points lost per hour awake (16 h awake ≈ 32 points) — gentle
  /// enough that a usual night (70) still reads "okay" in the evening.
  static const drainPerHourAwake = 2.0;

  /// Hours awake stop counting after this. A wake time older than a
  /// normal day (missed night, stale data) must not pin Charge at the
  /// floor — that reads as "you're exhausted" when we simply don't know.
  static const maxHoursAwake = 17.0;

  /// Active calories per point lost (400 kcal ≈ 16 points)…
  static const kcalPerPoint = 25.0;

  /// …but movement never costs more than this, so walking more is not
  /// punished harder than it should be (the app also asks you to move).
  static const maxActivityDrain = 15.0;

  /// Daytime stress 0–100 drains up to this many points.
  static const maxStressDrain = 10.0;

  /// Never show 0 — "empty" reads as alarming. Low enough to say "rest".
  static const floor = 5;

  // Level cut-offs.
  static const fullAt = 75;
  static const goodAt = 50;
  static const lowAt = 30;

  const HuxChargeCalculator();

  HuxCharge calculate({
    required PersonalBaseline baseline,
    required SleepSession? lastNight,
    required List<HealthSnapshot> todaySnapshots,
    required DateTime now,
  }) {
    if (baseline.insufficient) {
      return HuxCharge(
        value: null,
        morningCharge: null,
        level: null,
        label: 'Learning (${baseline.daysOfData} of '
            '${PersonalBaseline.minDaysRequired} nights)',
      );
    }

    final parts = <({String name, double score, double weight})>[];

    final baseHrv = baseline.medianHrvMs;
    final lastHrv = lastNight?.avgHrvMs;
    if (baseHrv != null && baseHrv > 0 && lastHrv != null) {
      final diff = (lastHrv - baseHrv) / baseHrv;
      parts.add((name: 'hrv', score: _component(diff, hrvSpanPct), weight: hrvWeight));
    }

    final baseSleep = baseline.medianTotalSleep;
    if (lastNight != null &&
        lastNight.segments.isNotEmpty &&
        baseSleep != null &&
        baseSleep.inMinutes > 0) {
      final diff = (lastNight.totalSleep.inMinutes - baseSleep.inMinutes) / baseSleep.inMinutes;
      parts.add((name: 'sleep', score: _component(diff, sleepSpanPct), weight: sleepWeight));
    }

    final baseHr = baseline.medianRestingHeartRateBpm;
    final lastHr = lastNight?.avgHeartRateBpm;
    if (baseHr != null && baseHr > 0 && lastHr != null) {
      // Lower resting HR than usual = better recovery.
      final diff = (baseHr - lastHr) / baseHr;
      parts.add((name: 'hr', score: _component(diff, restingHrSpanPct), weight: restingHrWeight));
    }

    if (parts.isEmpty) {
      return const HuxCharge(
        value: null,
        morningCharge: null,
        level: null,
        label: 'No sleep data last night',
      );
    }

    final totalWeight = parts.fold<double>(0, (s, p) => s + p.weight);
    final morning = parts.fold<double>(0, (s, p) => s + p.score * p.weight) / totalWeight;

    // ---- daytime drain ----
    var drain = 0.0;
    final wake = lastNight?.wakeTime.toUtc();
    final nowUtc = now.toUtc();
    if (wake != null && nowUtc.isAfter(wake)) {
      final hoursAwake = (nowUtc.difference(wake).inMinutes / 60.0).clamp(0.0, maxHoursAwake);
      drain += hoursAwake * drainPerHourAwake;
    }

    int? activeKcal;
    int? stress;
    for (final s in todaySnapshots.reversed) {
      activeKcal ??= s.activeEnergyKcal;
      stress ??= s.stressIndex;
      if (activeKcal != null && stress != null) break;
    }
    if (activeKcal != null && activeKcal > 0) {
      drain += (activeKcal / kcalPerPoint).clamp(0.0, maxActivityDrain);
    }
    if (stress != null && stress > 0) drain += (stress.clamp(0, 100) / 100) * maxStressDrain;

    final morningInt = morning.round().clamp(floor, 100).toInt();
    final value = (morning - drain).round().clamp(floor, 100).toInt();

    return HuxCharge(
      value: value,
      morningCharge: morningInt,
      level: _level(value),
      label: _label(_level(value)),
      reason: _reason(parts, drain),
    );
  }

  /// 70 at the user's usual; ±span moves it by 30 points; clamped 0–100.
  static double _component(double diff, double span) =>
      (usualNightCharge + (diff / span) * 30).clamp(0.0, 100.0);

  static ChargeLevel _level(int value) {
    if (value >= fullAt) return ChargeLevel.full;
    if (value >= goodAt) return ChargeLevel.good;
    if (value >= lowAt) return ChargeLevel.low;
    return ChargeLevel.veryLow;
  }

  static String _label(ChargeLevel level) => switch (level) {
        ChargeLevel.full => 'Fully charged',
        ChargeLevel.good => 'Good to go',
        ChargeLevel.low => 'Running low',
        ChargeLevel.veryLow => 'Recharge today',
      };

  /// The overnight signal furthest from usual explains the number; if the
  /// night was ordinary but the day was long, the drain does.
  static String? _reason(List<({String name, double score, double weight})> parts, double drain) {
    final strongest = parts.reduce(
        (a, b) => (a.score - usualNightCharge).abs() >= (b.score - usualNightCharge).abs() ? a : b);
    final offBy = strongest.score - usualNightCharge;

    if (offBy.abs() < 8) {
      return drain >= 25 ? 'A normal night — a long day is using it up.' : 'A normal night for you.';
    }
    final better = offBy > 0;
    return switch (strongest.name) {
      'hrv' => better ? 'Your body recovered better than usual overnight.' : 'Your body recovered less than usual overnight.',
      'sleep' => better ? 'You slept longer than usual.' : 'You slept less than usual.',
      _ => better ? 'Your heart rested more than usual overnight.' : 'Your heart worked harder than usual overnight.',
    };
  }
}
