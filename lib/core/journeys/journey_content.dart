/// Journey content as DATA: 2 programs, ~22 moves, ~30 meals.
/// Keep it small; add more only when usage shows people want it.
///
/// REVIEW STATUS: unreviewed. Moves and cues need a physiotherapist's
/// sign-off; meals and nutrition need a nutritionist's — see
/// docs/ROADMAP.md. Nutrition values are home-style estimates.
library;

import '../profile/user_profile.dart';
import 'journey_models.dart';

// ---------------------------------------------------------------------------
// Programs
// ---------------------------------------------------------------------------

const journeys = <JourneyDef>[
  JourneyDef(
    id: JourneyId.sleepReset21,
    title: 'Sleep Reset 21',
    subtitle: 'A steady wake time, an earlier bedtime and a 10-minute wind-down.',
    days: 21,
    highlights: [
      'Bedtime moves 15 minutes every 3 days — no shock',
      'A 10-minute evening wind-down you can do in bed clothes',
      'Simple dinners that help sleep',
    ],
  ),
  JourneyDef(
    id: JourneyId.fitIn30,
    title: 'Fit in 30',
    subtitle: 'Home workouts, no equipment, 12–20 minutes a day.',
    days: 30,
    highlights: [
      'Warm-up → workout → cool-down, every move explained',
      'Gets a little harder each week, with a weekly challenge',
      'Protein-rich meals that fit your diet and budget',
    ],
  ),
];

JourneyDef journeyDef(JourneyId id) => journeys.firstWhere((j) => j.id == id);

// ---------------------------------------------------------------------------
// Moves
// ---------------------------------------------------------------------------

const moves = <Move>[
  // ---- warm-up ----
  Move(id: 'march', name: 'March on the spot', kind: MoveKind.warmup, icon: 'walk',
      cues: ['Lift knees to hip height if you can', 'Swing your arms', 'Breathe easily'],
      easier: 'Smaller steps, hold a chair', harder: 'Light jog on the spot',
      stopIf: 'You feel dizzy or chest pain'),
  Move(id: 'arm_circles', name: 'Arm circles', kind: MoveKind.warmup, icon: 'arms',
      cues: ['Arms out to the sides', 'Small circles growing bigger', 'Change direction halfway'],
      easier: 'One arm at a time', harder: 'Bigger, faster circles',
      stopIf: 'Sharp shoulder pain'),
  Move(id: 'shoulder_rolls', name: 'Shoulder rolls', kind: MoveKind.warmup, icon: 'arms',
      cues: ['Shoulders up to ears, back, then down', 'Slow and smooth'],
      easier: 'Smaller rolls', harder: 'Add arm reaches overhead',
      stopIf: 'Neck or shoulder pain'),
  Move(id: 'hip_circles', name: 'Hip circles', kind: MoveKind.warmup, icon: 'hips',
      cues: ['Hands on hips, feet hip-width', 'Draw slow circles with your hips', 'Change direction'],
      easier: 'Smaller circles', harder: 'Wider stance, bigger circles',
      stopIf: 'Back pain'),
  Move(id: 'leg_swings', name: 'Leg swings', kind: MoveKind.warmup, icon: 'legs',
      cues: ['Hold a wall or chair', 'Swing one leg front and back, relaxed', 'Switch legs halfway'],
      easier: 'Small swings', harder: 'Higher swings, no support',
      stopIf: 'Hip or knee pain'),
  Move(id: 'cat_cow', name: 'Cat–cow', kind: MoveKind.warmup, icon: 'floor',
      cues: ['On hands and knees', 'Round your back, then gently arch', 'Move with your breath'],
      easier: 'Smaller movement', harder: 'Slower, fuller range',
      stopIf: 'Back or wrist pain'),

  // ---- strength / core / cardio ----
  Move(id: 'wall_pushup', name: 'Wall push-up', kind: MoveKind.strength, icon: 'push',
      cues: ['Hands on the wall at shoulder height', 'Body in one straight line', 'Lower chest to the wall, push back'],
      easier: 'Stand closer to the wall', harder: 'Knee push-up on the floor',
      stopIf: 'Wrist, elbow or shoulder pain'),
  Move(id: 'knee_pushup', name: 'Knee push-up', kind: MoveKind.strength, icon: 'push',
      cues: ['Knees down, hands under shoulders', 'Straight line knees to head', 'Lower slowly, push up'],
      easier: 'Wall push-up', harder: 'Full push-up',
      stopIf: 'Wrist or shoulder pain'),
  Move(id: 'chair_squat', name: 'Chair squat', kind: MoveKind.strength, icon: 'squat',
      cues: ['Feet hip-width, chair behind you', 'Sit back slowly, just touch the chair', 'Stand up through your heels'],
      easier: 'Use your hands on your knees', harder: 'Squat without the chair',
      stopIf: 'Knee pain'),
  Move(id: 'squat', name: 'Bodyweight squat', kind: MoveKind.strength, icon: 'squat',
      cues: ['Chest up, knees follow toes', 'Hips back like sitting', 'Go only as low as feels good'],
      easier: 'Chair squat', harder: 'Pause 2 s at the bottom',
      stopIf: 'Knee or back pain'),
  Move(id: 'glute_bridge', name: 'Glute bridge', kind: MoveKind.strength, icon: 'floor',
      cues: ['Lie on your back, knees bent', 'Squeeze your bottom, lift hips', 'Lower slowly'],
      easier: 'Smaller lift', harder: 'Hold 3 s at the top',
      stopIf: 'Back pain'),
  Move(id: 'static_lunge', name: 'Split squat', kind: MoveKind.strength, icon: 'legs',
      cues: ['One foot forward, one back', 'Lower the back knee gently', 'Front knee over the ankle'],
      easier: 'Hold a chair, go less low', harder: 'Slow 3 s down',
      stopIf: 'Knee pain'),
  Move(id: 'step_up', name: 'Step-ups', kind: MoveKind.cardio, icon: 'stairs',
      cues: ['Use the lowest stair', 'Whole foot on the step', 'Step up, step down, swap leads'],
      easier: 'Hold the railing', harder: 'Faster pace',
      stopIf: 'Dizziness, knee pain'),
  Move(id: 'step_jacks', name: 'Step jacks', kind: MoveKind.cardio, icon: 'jump',
      cues: ['Step one foot out as arms go up', 'Back in, then the other side', 'No jumping needed'],
      easier: 'Arms to shoulder height only', harder: 'Jumping jacks',
      stopIf: 'Breathless at rest, chest pain'),
  Move(id: 'plank_knees', name: 'Knee plank', kind: MoveKind.core, icon: 'plank',
      cues: ['Elbows under shoulders, knees down', 'Straight line knees to head', 'Breathe, don\'t hold your breath'],
      easier: 'Shorter hold', harder: 'Full plank',
      stopIf: 'Back pain'),
  Move(id: 'plank', name: 'Plank', kind: MoveKind.core, icon: 'plank',
      cues: ['Elbows under shoulders', 'Squeeze bottom and tummy', 'Hips level, not sagging'],
      easier: 'Knee plank', harder: 'Lift one foot slightly',
      stopIf: 'Back pain'),
  Move(id: 'bird_dog', name: 'Bird-dog', kind: MoveKind.core, icon: 'floor',
      cues: ['On hands and knees', 'Reach one arm and the opposite leg', 'Keep hips level, swap sides'],
      easier: 'Only lift the leg', harder: 'Hold 3 s each side',
      stopIf: 'Back pain'),
  Move(id: 'dead_bug', name: 'Dead bug', kind: MoveKind.core, icon: 'floor',
      cues: ['On your back, knees up at 90°', 'Lower opposite arm and leg slowly', 'Lower back stays on the floor'],
      easier: 'Only move the legs', harder: 'Straighter legs',
      stopIf: 'Back pain'),

  // ---- cool-down / wind-down ----
  Move(id: 'hamstring_stretch', name: 'Seated forward stretch', kind: MoveKind.stretch, icon: 'stretch',
      cues: ['Sit tall, legs out', 'Reach toward your toes, back long', 'Gentle — no bouncing'],
      easier: 'Bend your knees', harder: 'Hold longer',
      stopIf: 'Sharp pain'),
  Move(id: 'quad_stretch', name: 'Standing thigh stretch', kind: MoveKind.stretch, icon: 'stretch',
      cues: ['Hold a wall', 'Bring heel toward bottom', 'Knees together, swap legs'],
      easier: 'Lie on your side to do it', harder: 'Hold longer',
      stopIf: 'Knee pain'),
  Move(id: 'child_pose', name: 'Child\'s pose', kind: MoveKind.stretch, icon: 'floor',
      cues: ['Kneel, sit back on heels', 'Arms forward, forehead down', 'Slow breaths into your back'],
      easier: 'Pillow under hips', harder: 'Walk hands to each side',
      stopIf: 'Knee pain'),
  Move(id: 'legs_up_wall', name: 'Legs up the wall', kind: MoveKind.stretch, icon: 'floor',
      cues: ['Lie on your back, legs up a wall or bed', 'Arms relaxed', 'Breathe slowly'],
      easier: 'Bend your knees', harder: 'Stay longer',
      stopIf: 'Dizziness, if pregnant ask your doctor'),
  Move(id: 'box_breathing', name: 'Slow breathing', kind: MoveKind.breathing, icon: 'breath',
      cues: ['In through the nose for 4', 'Hold 4, out for 4, hold 4', 'Shoulders soft'],
      easier: 'In 3, out 5, no holds', harder: 'Out for 6',
      stopIf: 'You feel light-headed — breathe normally'),
];

Move moveById(String id) => moves.firstWhere((m) => m.id == id);

// ---------------------------------------------------------------------------
// Workouts
// ---------------------------------------------------------------------------

const _warmup = [
  MoveStep('march', seconds: 60),
  MoveStep('arm_circles', seconds: 30),
  MoveStep('hip_circles', seconds: 30),
  MoveStep('leg_swings', seconds: 40),
];

const _cooldown = [
  MoveStep('hamstring_stretch', seconds: 40),
  MoveStep('quad_stretch', seconds: 40),
  MoveStep('child_pose', seconds: 40),
  MoveStep('box_breathing', seconds: 60),
];

const _windDown = Workout(
  title: '10-minute wind-down',
  warmup: [MoveStep('shoulder_rolls', seconds: 40), MoveStep('cat_cow', seconds: 60)],
  main: [
    MoveStep('child_pose', seconds: 60),
    MoveStep('hamstring_stretch', seconds: 60),
    MoveStep('legs_up_wall', seconds: 120),
  ],
  cooldown: [MoveStep('box_breathing', seconds: 180)],
);

/// Fit in 30: weeks get longer work blocks / more rounds; every 7th day is
/// a challenge; days 4, 11, 18, 25 are easy recovery days.
Workout _fitWorkout(int day, FitnessLevel level) {
  final week = ((day - 1) ~/ 7).clamp(0, 3);
  final work = [30, 35, 40, 45][week];
  final rest = [30, 25, 20, 20][week];
  final rounds = [2, 2, 3, 3][week] + (level == FitnessLevel.regular ? 1 : 0);
  final beginner = level == FitnessLevel.beginner;

  if ({4, 11, 18, 25}.contains(day)) {
    return Workout(title: 'Easy recovery', warmup: _warmup, main: _windDown.main, cooldown: _cooldown);
  }
  if (day % 7 == 0 || day == 30) {
    // Challenge: how many in 60 s — beat it next week.
    return Workout(
      title: day == 30 ? 'Final challenge' : 'Challenge day',
      warmup: _warmup,
      main: [
        MoveStep(beginner ? 'chair_squat' : 'squat', seconds: 60, restSeconds: 45),
        MoveStep(beginner ? 'wall_pushup' : 'knee_pushup', seconds: 60, restSeconds: 45),
        MoveStep(beginner ? 'plank_knees' : 'plank', seconds: 45, restSeconds: 45),
        const MoveStep('step_jacks', seconds: 60, restSeconds: 30),
      ],
      cooldown: _cooldown,
    );
  }
  final upper = day.isOdd;
  final main = upper
      ? [
          MoveStep(beginner ? 'wall_pushup' : 'knee_pushup', seconds: work, restSeconds: rest),
          MoveStep('glute_bridge', seconds: work, restSeconds: rest),
          MoveStep(beginner ? 'plank_knees' : 'plank', seconds: work - 10, restSeconds: rest),
          MoveStep('step_jacks', seconds: work, restSeconds: rest),
        ]
      : [
          MoveStep(beginner ? 'chair_squat' : 'squat', seconds: work, restSeconds: rest),
          MoveStep('bird_dog', seconds: work, restSeconds: rest),
          MoveStep(beginner ? 'step_up' : 'static_lunge', seconds: work, restSeconds: rest),
          MoveStep('dead_bug', seconds: work, restSeconds: rest),
        ];
  return Workout(title: upper ? 'Push & core' : 'Legs & balance', warmup: _warmup, main: main, rounds: rounds, cooldown: _cooldown);
}

const _sleepTips = [
  'Same wake time every day — even Sunday. That is the anchor.',
  'Get 10 minutes of morning light (balcony or a short walk).',
  'Last chai or coffee before 2 PM today.',
  'Dinner at least 2–3 hours before bed.',
  'Phone on silent and out of reach for the wind-down.',
  'Keep the room cool and dark — a fan and a dark curtain help.',
  'A short afternoon nap is fine: under 20 minutes, before 3 PM.',
  'If you can\'t sleep in 20 minutes, get up, sit in dim light, come back.',
  'Walk 10 minutes after dinner — gentle, not a workout.',
  'Write tomorrow\'s to-do list before the wind-down so your mind can rest.',
  'Warm bath or wash before bed helps you feel sleepy.',
  'Heavy, fried or very spicy dinners make sleep lighter — keep it simple.',
  'Weekend lie-in? Keep it within 1 hour of your wake time.',
  'Dim the lights an hour before bed.',
  'No screens in bed — the bed is for sleep.',
  'Notice your energy today vs day 1.',
  'Stress? Try the slow breathing for 3 extra minutes.',
  'Late work call? Do the wind-down anyway, even 5 minutes.',
  'Keep water by the bed, but go easy after 8 PM.',
  'Your new bedtime should feel normal now — protect it.',
  'Last day: pick the 2 habits you\'ll keep.',
];

/// The lighter session offered on the first period days (Cycle).
const Workout gentleWorkout = Workout(title: 'Gentle day', warmup: _warmup, main: [
  MoveStep('cat_cow', seconds: 60),
  MoveStep('child_pose', seconds: 60),
  MoveStep('legs_up_wall', seconds: 120),
], cooldown: [MoveStep('box_breathing', seconds: 120)]);

/// The day plan for [id] on [day] (1-based).
JourneyDay journeyDay(JourneyId id, int day, FitnessLevel level) {
  switch (id) {
    case JourneyId.sleepReset21:
      return JourneyDay(day: day, focus: _sleepTips[(day - 1) % _sleepTips.length], workout: _windDown);
    case JourneyId.fitIn30:
      final w = _fitWorkout(day, level);
      return JourneyDay(
        day: day,
        focus: w.title == 'Easy recovery'
            ? 'Recovery day: move gently, stretch, sleep well.'
            : (day % 7 == 0 || day == 30)
                ? 'Challenge: count your reps in each 60 s and write them down.'
                : 'Slow and controlled beats fast. Stop if anything hurts.',
        workout: w,
        challenge: day % 7 == 0 || day == 30,
      );
  }
}

// ---------------------------------------------------------------------------
// Meals (approximate, home-style; unreviewed)
// ---------------------------------------------------------------------------

const _vegAll = {Diet.veg, Diet.egg, Diet.nonVeg, Diet.jain};
const _vegNoJain = {Diet.veg, Diet.egg, Diet.nonVeg};
const _egg = {Diet.egg, Diet.nonVeg};
const _nonVeg = {Diet.nonVeg};

const meals = <MealOption>[
  // ---- breakfast ----
  MealOption(id: 'besan_chilla', name: 'Besan chilla + curd', portion: '2 chillas, 1 katori curd',
      slots: {MealSlot.breakfast, MealSlot.dinner}, diets: _vegNoJain, budget: Budget.low,
      proteinG: 18, kcal: 330, carbsG: 34, fatG: 12),
  MealOption(id: 'moong_chilla', name: 'Moong dal chilla + chutney', portion: '2 chillas',
      slots: {MealSlot.breakfast}, diets: _vegAll, budget: Budget.low,
      proteinG: 16, kcal: 290, carbsG: 38, fatG: 7),
  MealOption(id: 'poha_peanuts', name: 'Poha with peanuts', portion: '1 plate + 1 tbsp peanuts',
      slots: {MealSlot.breakfast}, diets: _vegNoJain, budget: Budget.low,
      proteinG: 9, kcal: 330, carbsG: 52, fatG: 10),
  MealOption(id: 'idli_sambar', name: 'Idli + sambar', portion: '3 idlis, 1 katori sambar',
      slots: {MealSlot.breakfast}, diets: _vegNoJain, budget: Budget.low,
      proteinG: 12, kcal: 320, carbsG: 60, fatG: 3),
  MealOption(id: 'oats_milk', name: 'Oats with milk + banana', portion: '½ cup oats, 1 glass milk',
      slots: {MealSlot.breakfast}, diets: _vegAll, budget: Budget.low,
      proteinG: 14, kcal: 360, carbsG: 58, fatG: 8),
  MealOption(id: 'egg_bhurji_roti', name: 'Egg bhurji + 2 roti', portion: '2 eggs, 2 roti',
      slots: {MealSlot.breakfast, MealSlot.dinner}, diets: _egg, budget: Budget.low,
      proteinG: 20, kcal: 400, carbsG: 38, fatG: 18),
  MealOption(id: 'boiled_eggs_toast', name: 'Boiled eggs + toast', portion: '2 eggs, 2 slices',
      slots: {MealSlot.breakfast}, diets: _egg, budget: Budget.low,
      proteinG: 18, kcal: 300, carbsG: 26, fatG: 11),
  MealOption(id: 'paneer_paratha', name: 'Paneer paratha + curd', portion: '1 paratha, 1 katori curd',
      slots: {MealSlot.breakfast}, diets: _vegNoJain, budget: Budget.mid,
      proteinG: 20, kcal: 420, carbsG: 40, fatG: 20),
  MealOption(id: 'greek_yogurt_fruit', name: 'Hung curd + fruit + nuts', portion: '1 katori, 1 fruit, 10 nuts',
      slots: {MealSlot.breakfast, MealSlot.snack}, diets: _vegAll, budget: Budget.mid,
      proteinG: 14, kcal: 280, carbsG: 28, fatG: 12),

  // ---- lunch / dinner ----
  MealOption(id: 'dal_rice_salad', name: 'Dal chawal + salad', portion: '1 katori dal, 1 katori rice',
      slots: {MealSlot.lunch, MealSlot.dinner}, diets: _vegAll, budget: Budget.low,
      proteinG: 14, kcal: 420, carbsG: 72, fatG: 6),
  MealOption(id: 'rajma_rice', name: 'Rajma chawal', portion: '1 katori rajma, 1 katori rice',
      slots: {MealSlot.lunch}, diets: _vegNoJain, budget: Budget.low,
      proteinG: 15, kcal: 450, carbsG: 76, fatG: 7),
  MealOption(id: 'chole_roti', name: 'Chole + 2 roti', portion: '1 katori chole, 2 roti',
      slots: {MealSlot.lunch, MealSlot.dinner}, diets: _vegNoJain, budget: Budget.low,
      proteinG: 16, kcal: 470, carbsG: 70, fatG: 12),
  MealOption(id: 'soya_rice', name: 'Soya chunk curry + rice', portion: '1 katori curry, 1 katori rice',
      slots: {MealSlot.lunch, MealSlot.dinner}, diets: _vegNoJain, budget: Budget.low,
      proteinG: 24, kcal: 430, carbsG: 60, fatG: 8),
  MealOption(id: 'dal_roti_sabzi', name: 'Mixed dal + 2 roti + sabzi', portion: '1 katori each',
      slots: {MealSlot.lunch, MealSlot.dinner}, diets: _vegAll, budget: Budget.low,
      proteinG: 15, kcal: 450, carbsG: 66, fatG: 11),
  MealOption(id: 'khichdi_curd', name: 'Moong khichdi + curd', portion: '1½ katori khichdi, 1 katori curd',
      slots: {MealSlot.lunch, MealSlot.dinner}, diets: _vegAll, budget: Budget.low,
      proteinG: 15, kcal: 400, carbsG: 62, fatG: 8),
  MealOption(id: 'sambar_rice_poriyal', name: 'Sambar rice + poriyal', portion: '1 plate',
      slots: {MealSlot.lunch}, diets: _vegNoJain, budget: Budget.low,
      proteinG: 12, kcal: 430, carbsG: 74, fatG: 9),
  MealOption(id: 'paneer_bhurji_roti', name: 'Paneer bhurji + 2 roti', portion: '100 g paneer, 2 roti',
      slots: {MealSlot.lunch, MealSlot.dinner}, diets: _vegNoJain, budget: Budget.mid,
      proteinG: 24, kcal: 520, carbsG: 40, fatG: 26),
  MealOption(id: 'egg_curry_roti', name: 'Egg curry + 2 roti', portion: '2 eggs, 2 roti',
      slots: {MealSlot.lunch, MealSlot.dinner}, diets: _egg, budget: Budget.low,
      proteinG: 19, kcal: 460, carbsG: 42, fatG: 20),
  MealOption(id: 'chicken_curry_roti', name: 'Chicken curry + 2 roti', portion: '1 katori curry, 2 roti',
      slots: {MealSlot.lunch, MealSlot.dinner}, diets: _nonVeg, budget: Budget.mid,
      proteinG: 30, kcal: 520, carbsG: 40, fatG: 20),
  MealOption(id: 'fish_curry_rice', name: 'Fish curry + rice', portion: '1 piece fish, 1 katori rice',
      slots: {MealSlot.lunch, MealSlot.dinner}, diets: _nonVeg, budget: Budget.mid,
      proteinG: 26, kcal: 480, carbsG: 55, fatG: 14),
  MealOption(id: 'grilled_chicken_salad', name: 'Grilled chicken + salad + roti', portion: '120 g chicken, 1 roti',
      slots: {MealSlot.lunch, MealSlot.dinner}, diets: _nonVeg, budget: Budget.high,
      proteinG: 35, kcal: 430, carbsG: 25, fatG: 16),
  MealOption(id: 'tofu_veg_rice', name: 'Tofu stir-fry + rice', portion: '120 g tofu, 1 katori rice',
      slots: {MealSlot.lunch, MealSlot.dinner}, diets: _vegNoJain, budget: Budget.high,
      proteinG: 22, kcal: 450, carbsG: 52, fatG: 15),
  MealOption(id: 'paneer_tikka', name: 'Paneer tikka + salad', portion: '120 g paneer',
      slots: {MealSlot.dinner}, diets: _vegNoJain, budget: Budget.high,
      proteinG: 24, kcal: 380, carbsG: 12, fatG: 26),

  // ---- snacks ----
  MealOption(id: 'roasted_chana', name: 'Roasted chana', portion: '1 handful (30 g)',
      slots: {MealSlot.snack}, diets: _vegAll, budget: Budget.low,
      proteinG: 6, kcal: 110, carbsG: 18, fatG: 2),
  MealOption(id: 'sprouts_chaat', name: 'Sprouts chaat', portion: '1 katori',
      slots: {MealSlot.snack}, diets: _vegNoJain, budget: Budget.low,
      proteinG: 9, kcal: 150, carbsG: 24, fatG: 2),
  MealOption(id: 'buttermilk_makhana', name: 'Buttermilk + roasted makhana', portion: '1 glass, 1 cup',
      slots: {MealSlot.snack}, diets: _vegAll, budget: Budget.low,
      proteinG: 7, kcal: 160, carbsG: 22, fatG: 4),
  MealOption(id: 'peanuts_banana', name: 'Peanuts + banana', portion: '1 handful + 1 banana',
      slots: {MealSlot.snack}, diets: _vegAll, budget: Budget.low,
      proteinG: 8, kcal: 260, carbsG: 30, fatG: 13),
  MealOption(id: 'milk_glass', name: 'Glass of milk (haldi optional)', portion: '1 glass',
      slots: {MealSlot.snack}, diets: _vegAll, budget: Budget.low,
      proteinG: 8, kcal: 150, carbsG: 12, fatG: 8),
  MealOption(id: 'boiled_egg_snack', name: 'Boiled eggs', portion: '2 eggs',
      slots: {MealSlot.snack}, diets: _egg, budget: Budget.low,
      proteinG: 12, kcal: 150, carbsG: 1, fatG: 10),
  MealOption(id: 'paneer_cubes', name: 'Paneer cubes + chaat masala', portion: '75 g',
      slots: {MealSlot.snack}, diets: _vegAll, budget: Budget.mid,
      proteinG: 14, kcal: 220, carbsG: 3, fatG: 16),
];

/// Two options per meal slot for [day], filtered by [diet] and [budget]
/// (cheaper options are always allowed). Rotates by day so the week
/// isn't the same food. For the sleep program, dinners are light ones.
Map<MealSlot, List<MealOption>> mealsForDay({
  required int day,
  required Diet diet,
  required Budget budget,
  bool lightDinner = false,
}) {
  final out = <MealSlot, List<MealOption>>{};
  for (final slot in MealSlot.values) {
    var pool = meals
        .where((m) => m.slots.contains(slot) && m.diets.contains(diet) && m.budget.index <= budget.index)
        .toList();
    if (slot == MealSlot.dinner && lightDinner) {
      final light = pool.where((m) => m.kcal <= 450).toList();
      if (light.length >= 2) pool = light;
    }
    if (pool.isEmpty) continue;
    // Highest protein first, then rotate by day.
    pool.sort((a, b) => b.proteinG.compareTo(a.proteinG));
    final start = (day - 1) % pool.length;
    out[slot] = [
      pool[start],
      if (pool.length > 1) pool[(start + 1) % pool.length],
    ];
  }
  return out;
}
