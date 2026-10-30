/// Journeys — guided multi-day programs (sleep, food, movement) with ONE
/// quiet Home card a day. Pure Dart: no Flutter, no I/O. Content lives in
/// journey_content.dart as data, so programs, moves and meals can grow
/// without touching screens.
library;

import '../profile/user_profile.dart';

enum JourneyId { sleepReset21, fitIn30 }

/// Food budget per meal, shown as ranges (prices vary by city).
enum Budget { low, mid, high }

extension BudgetLabel on Budget {
  String get symbol => switch (this) {
        Budget.low => '₹',
        Budget.mid => '₹₹',
        Budget.high => '₹₹₹',
      };

  String get range => switch (this) {
        Budget.low => 'under ~₹40 a meal',
        Budget.mid => '~₹40–100 a meal',
        Budget.high => '~₹100+ a meal',
      };
}

enum FitnessLevel { beginner, regular }

extension FitnessLevelLabel on FitnessLevel {
  String get label => switch (this) {
        FitnessLevel.beginner => 'Just starting',
        FitnessLevel.regular => 'I move regularly',
      };
}

/// The three things a journey day asks for — never more.
enum DayItem { sleep, food, move }

enum MoveKind { warmup, strength, cardio, core, stretch, breathing }

/// One exercise. [icon] is a name the UI maps to an icon until real
/// illustrations exist (see docs/ROADMAP.md: own/licensed visuals).
class Move {
  final String id;
  final String name;
  final MoveKind kind;
  final String icon;

  /// 2–3 short form cues, said in plain words.
  final List<String> cues;
  final String easier;
  final String harder;

  /// When to stop this move.
  final String stopIf;

  const Move({
    required this.id,
    required this.name,
    required this.kind,
    required this.icon,
    required this.cues,
    required this.easier,
    required this.harder,
    required this.stopIf,
  });
}

/// A move in a workout: done for [seconds] (timed) or [reps].
class MoveStep {
  final String moveId;
  final int? seconds;
  final int? reps;

  /// Rest after this step (seconds).
  final int restSeconds;

  const MoveStep(this.moveId, {this.seconds, this.reps, this.restSeconds = 0})
      : assert(seconds != null || reps != null);
}

class Workout {
  final String title;
  final List<MoveStep> warmup;
  final List<MoveStep> main;

  /// How many times [main] is repeated.
  final int rounds;
  final List<MoveStep> cooldown;

  const Workout({
    required this.title,
    required this.warmup,
    required this.main,
    this.rounds = 1,
    required this.cooldown,
  });

  /// Steps in the order they're done (main repeated [rounds] times).
  List<MoveStep> get allSteps => [
        ...warmup,
        for (var r = 0; r < rounds; r++) ...main,
        ...cooldown,
      ];

  /// Rough length in minutes (reps count as ~3 s each).
  int get minutes {
    final secs = allSteps.fold<int>(
        0, (s, st) => s + (st.seconds ?? (st.reps! * 3)) + st.restSeconds);
    return (secs / 60).ceil();
  }
}

class JourneyDay {
  /// 1-based.
  final int day;

  /// One short line: today's idea.
  final String focus;
  final Workout workout;

  /// A weekly "test yourself" day.
  final bool challenge;

  const JourneyDay({required this.day, required this.focus, required this.workout, this.challenge = false});
}

class JourneyDef {
  final JourneyId id;
  final String title;
  final String subtitle;
  final int days;

  /// What the program promises, in 3 short lines.
  final List<String> highlights;

  const JourneyDef({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.days,
    required this.highlights,
  });
}

enum MealSlot { breakfast, lunch, snack, dinner }

extension MealSlotLabel on MealSlot {
  String get label => switch (this) {
        MealSlot.breakfast => 'Breakfast',
        MealSlot.lunch => 'Lunch',
        MealSlot.snack => 'Snack',
        MealSlot.dinner => 'Dinner',
      };
}

/// A home-style meal idea with approximate nutrition for the portion
/// given. Values are estimates (unreviewed until a nutritionist signs off).
class MealOption {
  final String id;
  final String name;
  final String portion;
  final Set<MealSlot> slots;

  /// Which diets can eat it. Jain = no onion, garlic or root vegetables.
  final Set<Diet> diets;
  final Budget budget;
  final double proteinG;
  final double kcal;
  final double carbsG;
  final double fatG;

  const MealOption({
    required this.id,
    required this.name,
    required this.portion,
    required this.slots,
    required this.diets,
    required this.budget,
    required this.proteinG,
    required this.kcal,
    required this.carbsG,
    required this.fatG,
  });
}
