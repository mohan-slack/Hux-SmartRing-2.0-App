/// HUX plan library — six plans, each built on published research, in
/// HUX's own words and progressions (no copied programme content).
///
/// 1. First Steps — gentle build to a 30-minute walk (WHO: 150 min/week).
/// 2. Brisk 100 — walk at ~100 steps/min, the moderate-intensity cadence
///    from the CADENCE-Adults studies (Tudor-Locke; ~130/min = vigorous).
/// 3. Japanese Interval Walk — 3 min fast / 3 min slow ×5, ≥4 days/week
///    (Nose & Masuki, Shinshu University; fitness gains vs steady walking).
/// 4. Zero to 5K — 9-week walk-run build to 30 minutes of running,
///    3 sessions/week (the structure popularised by the NHS Couch to 5K).
/// 5. Stair Snacks — 1–2 minute vigorous bursts, ~3 a day (VILPA,
///    Stamatakis et al. 2022, Nature Medicine, 25,241 non-exercisers).
/// 6. Steady & Strong 60+ — strength, balance and walking, 3×/week,
///    inspired by the Otago programme (fewer falls in older adults).
library;

import 'plan_models.dart';

const _m = 60;

Segment _wu([int min = 5]) => Segment(SegmentKind.warmup, min * _m);
Segment _cd([int min = 5]) => Segment(SegmentKind.cooldown, min * _m);

List<Session> _weekly(int weeks, int perWeek, List<Segment> Function(int week) build) => [
      for (var w = 1; w <= weeks; w++)
        for (var d = 1; d <= perWeek; d++) Session(week: w, day: d, segments: build(w)),
    ];

final _firstSteps = Plan(
  id: 'first_steps',
  name: 'First Steps',
  tagline: 'From 10 minutes to a confident 30-minute walk in 6 weeks',
  evidence: 'WHO recommends at least 150 minutes of moderate activity a week. '
      'Five 30-minute walks gets you there — this plan builds up to it gently.',
  level: PlanLevel.gentle,
  weeks: 6,
  sessionsPerWeek: 5,
  sessions: _weekly(6, 5, (w) {
    const mins = [10, 15, 20, 25, 30, 30];
    if (w < 6) return [Segment(SegmentKind.walk, mins[w - 1] * _m)];
    return [_wu(), const Segment(SegmentKind.brisk, 20 * _m), _cd()];
  }),
);

final _brisk100 = Plan(
  id: 'brisk_100',
  name: 'Brisk 100',
  tagline: 'Walk at about 100 steps a minute — real exercise, no gym',
  evidence: 'Studies (CADENCE-Adults, Tudor-Locke) found ~100 steps per minute is '
      'moderate-intensity exercise for most adults, and ~130 is vigorous. '
      'Check yourself: count steps for 15 seconds — 25 or more means you\'re there.',
  level: PlanLevel.beginner,
  weeks: 6,
  sessionsPerWeek: 4,
  sessions: _weekly(6, 4, (w) {
    const brisk = [10, 15, 20, 25, 30, 30];
    return [_wu(3), Segment(SegmentKind.brisk, brisk[w - 1] * _m), _cd(3)];
  }),
);

final _intervalWalk = Plan(
  id: 'interval_walk',
  name: 'Japanese Interval Walk',
  tagline: '3 minutes fast, 3 minutes easy — fitter in weeks',
  evidence: 'Developed at Shinshu University (Nose & Masuki): alternating 3 minutes of '
      'fast walking (breathing hard, talking is difficult) with 3 minutes of easy '
      'walking, 5 rounds, 4+ days a week. In studies it improved fitness, leg '
      'strength and blood pressure more than steady walking.',
  level: PlanLevel.intermediate,
  weeks: 8,
  sessionsPerWeek: 4,
  needsReadinessCheck: true,
  sessions: _weekly(8, 4, (w) {
    final sets = w == 1 ? 3 : (w == 2 ? 4 : 5);
    return [
      _wu(3),
      for (var i = 0; i < sets; i++) ...[
        const Segment(SegmentKind.fast, 3 * _m),
        const Segment(SegmentKind.slow, 3 * _m),
      ],
      _cd(3),
    ];
  }),
);

final _zeroTo5k = Plan(
  id: 'zero_to_5k',
  name: 'Zero to 5K',
  tagline: 'From walking to 30 minutes of running in 9 weeks',
  evidence: 'Walk-run plans like the NHS Couch to 5K have helped millions start '
      'running: 3 sessions a week with rest days between, running a little longer '
      'each week. HUX\'s version adds a 5-minute warm-up and cool-down walk.',
  level: PlanLevel.advanced,
  weeks: 9,
  sessionsPerWeek: 3,
  needsReadinessCheck: true,
  sessions: _weekly(9, 3, (w) {
    // (run seconds, walk seconds, repeats) per week.
    const table = [
      (60, 90, 8),
      (90, 120, 6),
      (120, 90, 6),
      (180, 90, 5),
      (300, 180, 3),
      (480, 120, 3),
      (720, 120, 2),
      (1500, 0, 1),
      (1800, 0, 1),
    ];
    final (run, walk, reps) = table[w - 1];
    return [
      _wu(),
      for (var i = 0; i < reps; i++) ...[
        Segment(SegmentKind.run, run),
        if (walk > 0 && i < reps - 1) Segment(SegmentKind.walk, walk),
      ],
      _cd(),
    ];
  }),
);

final _stairSnacks = Plan(
  id: 'stair_snacks',
  name: 'Stair Snacks',
  tagline: '1–2 minute bursts, about 3 a day — no workout clothes needed',
  evidence: 'A 2022 Nature Medicine study (Stamatakis et al., 25,241 adults who '
      'didn\'t exercise) linked about three 1–2 minute bursts of vigorous daily '
      'activity — climbing stairs fast, brisk uphill walking, carrying heavy bags — '
      'with markedly lower risk of early death. Each session here is one snack; '
      'aim for three spread across the day.',
  level: PlanLevel.intermediate,
  weeks: 4,
  sessionsPerWeek: 21,
  needsReadinessCheck: true,
  sessions: _weekly(4, 21, (w) => [Segment(SegmentKind.snack, w <= 2 ? 60 : 90)]),
);

final _steadyStrong = Plan(
  id: 'steady_strong_60',
  name: 'Steady & Strong 60+',
  tagline: 'Strength, balance and walking for steadier legs',
  evidence: 'Inspired by the Otago programme for older adults, where home strength '
      'and balance exercises with regular walking reduced falls by about a third. '
      'Always keep a sturdy chair or kitchen counter within reach.',
  level: PlanLevel.gentle,
  weeks: 8,
  sessionsPerWeek: 3,
  safetyNote: 'Hold a chair or counter for every balance exercise. If you have had '
      'a fall, dizziness, or joint surgery, check with your doctor or physiotherapist first.',
  sessions: _weekly(8, 3, (w) {
    const walkMins = [10, 10, 15, 15, 20, 20, 25, 30];
    return [
      const Segment(SegmentKind.exercise, 60,
          instruction: 'Sit to stand: from a chair, stand up slowly and sit back down. Repeat 5 to 10 times.'),
      const Segment(SegmentKind.exercise, 60,
          instruction: 'Heel raises: holding the chair, rise onto your toes, then lower slowly. Repeat 10 times.'),
      const Segment(SegmentKind.exercise, 60,
          instruction: 'One-leg stand: holding the counter, stand on one leg for 10 seconds, then the other. Repeat.'),
      const Segment(SegmentKind.exercise, 60,
          instruction: 'Heel-to-toe walk: along a wall, place one heel right in front of the other toes, 10 steps.'),
      Segment(SegmentKind.walk, walkMins[w - 1] * _m),
    ];
  }),
);

final planLibrary = <Plan>[_firstSteps, _brisk100, _intervalWalk, _stairSnacks, _steadyStrong, _zeroTo5k];

Plan? planById(String id) {
  for (final p in planLibrary) {
    if (p.id == id) return p;
  }
  return null;
}

/// Plans that fit the user's onboarding answers, best first.
List<String> recommendedPlanIds({required bool elder, required bool fitGoal, required bool weightOrSugar, required bool desk}) {
  final ids = <String>[];
  void add(String id) {
    if (!ids.contains(id)) ids.add(id);
  }

  if (elder) {
    add('steady_strong_60');
    add('first_steps');
  }
  if (fitGoal) {
    add('interval_walk');
    add('zero_to_5k');
  }
  if (weightOrSugar) {
    add('brisk_100');
    add('first_steps');
  }
  if (desk) add('stair_snacks');
  if (ids.isEmpty) {
    add('first_steps');
    add('brisk_100');
  }
  return ids;
}
