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
/// 2. A FLOOR ON "USUAL": comparing only with yourself hides chronic
///    short sleep (5 h every night would read "usual" = 70). Under
///    [minHealthySleep] the morning charge is pulled down and capped, so
///    habitually short nights never read "Good to go".
/// 3. DAYTIME DRAIN — from the morning charge, energy drains gently with
///    time awake (after a short morning grace) and daytime stress.
///    Movement does NOT drain it: the app asks you to walk, so walking
///    must never make the number worse.
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

  /// True when last night was under [HuxChargeCalculator.minHealthySleep]
  /// and that pulled the morning charge down (even if it was "usual").
  final bool shortSleep;

  const HuxCharge({
    required this.value,
    required this.morningCharge,
    required this.level,
    required this.label,
    this.reason,
    this.shortSleep = false,
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

  /// How rested the user SAID they feel (morning check-in, 1–5). Sensors
  /// can't see this; for phone-only users it's half of what we know.
  static const feelWeight = 0.3;
  static const feelScores = [25.0, 45.0, 65.0, 78.0, 90.0];

  // Short-sleep floor (adult guide: 7–9 h; NSF / AASM).
  /// Under this, the morning charge is lowered even if the night was
  /// "usual" for you.
  static const minHealthySleep = Duration(hours: 7);

  /// Points off the morning charge per hour under [minHealthySleep].
  static const shortSleepPenaltyPerHour = 8.0;

  /// …and the morning charge can't be higher than this "absolute" score
  /// + [shortSleepCapMargin], where the absolute score is 70 at 7 h and
  /// falls [absolutePerHour] per hour short (5 h → 20 → cap 45).
  static const absolutePerHour = 25.0;
  static const shortSleepCapMargin = 25.0;

  /// Over this, extra sleep is not a bonus (illness, catch-up, data
  /// from two sources): the sleep signal reads as "usual".
  static const longSleep = Duration(hours: 10);

  // Daytime drain.
  /// Hours after waking with no drain (getting going isn't tiredness).
  static const graceHours = 2.0;

  /// Points lost per hour awake after the grace (16 h awake ≈ 21 points)
  /// — a usual night (70) ends the day around 50, not "empty".
  static const drainPerHourAwake = 1.5;

  /// Hours awake stop counting after this. A wake time older than a
  /// normal day (missed night, stale data) must not pin Charge at the
  /// floor — that reads as "you're exhausted" when we simply don't know.
  static const maxHoursAwake = 17.0;

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
    int? feel,
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
    final slept = lastNight == null || lastNight.segments.isEmpty ? null : lastNight.totalSleep;
    if (slept != null && baseSleep != null && baseSleep.inMinutes > 0) {
      var diff = (slept.inMinutes - baseSleep.inMinutes) / baseSleep.inMinutes;
      // Very long nights are not "better recovery".
      if (slept > longSleep && diff > 0) diff = 0;
      parts.add((name: 'sleep', score: _component(diff, sleepSpanPct), weight: sleepWeight));
    }

    final baseHr = baseline.medianRestingHeartRateBpm;
    final lastHr = lastNight?.avgHeartRateBpm;
    if (baseHr != null && baseHr > 0 && lastHr != null) {
      // Lower resting HR than usual = better recovery.
      final diff = (baseHr - lastHr) / baseHr;
      parts.add((name: 'hr', score: _component(diff, restingHrSpanPct), weight: restingHrWeight));
    }

    if (feel != null && feel >= 1 && feel <= 5 && parts.isNotEmpty) {
      parts.add((name: 'feel', score: feelScores[feel - 1], weight: feelWeight));
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
    var morning = parts.fold<double>(0, (s, p) => s + p.score * p.weight) / totalWeight;

    // ---- short-sleep floor (absolute, not just vs your usual) ----
    var short = false;
    if (slept != null && slept < minHealthySleep) {
      final hoursShort = (minHealthySleep - slept).inMinutes / 60.0;
      final absolute = (usualNightCharge - hoursShort * absolutePerHour).clamp(0.0, 100.0);
      final lowered = morning - hoursShort * shortSleepPenaltyPerHour;
      final capped = absolute + shortSleepCapMargin;
      morning = lowered < capped ? lowered : capped;
      short = hoursShort >= 0.25;
    }

    // ---- daytime drain ----
    var drain = 0.0;
    var hoursAwake = 0.0;
    final wake = lastNight?.wakeTime.toUtc();
    final nowUtc = now.toUtc();
    if (wake != null && nowUtc.isAfter(wake)) {
      hoursAwake = (nowUtc.difference(wake).inMinutes / 60.0).clamp(0.0, maxHoursAwake);
      drain += (hoursAwake - graceHours).clamp(0.0, maxHoursAwake) * drainPerHourAwake;
    }

    // Latest daytime stress reading (movement deliberately not counted).
    int? stress;
    for (final s in todaySnapshots.reversed) {
      stress ??= s.stressIndex;
      if (stress != null) break;
    }
    if (stress != null && stress > 0) drain += (stress.clamp(0, 100) / 100) * maxStressDrain;

    final morningInt = morning.round().clamp(floor, 100).toInt();
    final value = (morning - drain).round().clamp(floor, 100).toInt();

    final level = _level(value);
    // A good morning that has simply been used up by a long day isn't
    // "running low" — it's the normal end of a day.
    final windingDown = level == ChargeLevel.low && morningInt >= goodAt && hoursAwake >= 11;
    return HuxCharge(
      value: value,
      morningCharge: morningInt,
      level: level,
      label: windingDown ? 'Winding down' : _label(level),
      reason: _reason(parts, drain, short ? slept : null),
      shortSleep: short,
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
  static String? _reason(List<({String name, double score, double weight})> parts, double drain, Duration? shortSleep) {
    final strongest = parts.reduce(
        (a, b) => (a.score - usualNightCharge).abs() >= (b.score - usualNightCharge).abs() ? a : b);
    final offBy = strongest.score - usualNightCharge;

    if (offBy.abs() < 8) {
      if (shortSleep != null) {
        final h = shortSleep.inMinutes ~/ 60, m = (shortSleep.inMinutes % 60).toString().padLeft(2, '0');
        return 'Usual for you, but ${h}h ${m}m is under the 7 hours most adults need.';
      }
      return drain >= 18 ? 'A normal night — a long day is using it up.' : 'A normal night for you.';
    }
    final better = offBy > 0;
    return switch (strongest.name) {
      'hrv' => better ? 'Your body recovered better than usual overnight.' : 'Your body recovered less than usual overnight.',
      'sleep' => better ? 'You slept longer than usual.' : 'You slept less than usual.',
      'feel' => better ? 'You said you feel rested.' : 'You said you feel tired.',
      _ => better ? 'Your heart rested more than usual overnight.' : 'Your heart worked harder than usual overnight.',
    };
  }
}
