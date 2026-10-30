/// What the coach is told about you: a SMALL summary of numbers and
/// labels — never your name, email, raw readings, timestamps or
/// location. The user sees exactly this list ("What HUX shares") before
/// agreeing, and can turn sharing off at any time.
library;

import '../cycle/cycle_service.dart';
import '../food/food_log_service.dart';
import '../meaning/readout_service.dart';
import '../profile/profile_service.dart';
import '../profile/user_profile.dart';
import '../progress/progress_service.dart';
import '../storage/health_store.dart';
import '../trends/night_row.dart';

class CoachContext {
  final List<String> goals;
  final String? audience;
  final String? dayType;
  final String? diet;
  final String? fasting;
  final CoachStyle? style;
  final AppLanguage? language;

  /// "morning" / "afternoon" / "evening" / "night" — so advice fits the hour.
  final String partOfDay;

  final int? charge;
  final String? chargeLabel;
  final String? effort;
  final int? stepsToday;
  final int? stepGoal;
  final String? targetBedtime;
  final int? lastNightSleepMin;
  final int? usualSleepMin;
  final int? streakDays;
  final int? moveDaysThisWeek;
  final int? proteinTodayG;
  final int? proteinGoalG;

  /// ONE word ("Luteal"), only if the user turned it on in Cycle.
  final String? cyclePhase;

  const CoachContext({
    this.goals = const [],
    this.audience,
    this.dayType,
    this.diet,
    this.fasting,
    this.style,
    this.language,
    required this.partOfDay,
    this.charge,
    this.chargeLabel,
    this.effort,
    this.stepsToday,
    this.stepGoal,
    this.targetBedtime,
    this.lastNightSleepMin,
    this.usualSleepMin,
    this.streakDays,
    this.moveDaysThisWeek,
    this.proteinTodayG,
    this.proteinGoalG,
    this.cyclePhase,
  });

  /// Sent to the backend. Only filled fields; flat and small.
  Map<String, Object?> toJson() {
    final m = <String, Object?>{
      'partOfDay': partOfDay,
      if (goals.isNotEmpty) 'goals': goals,
      'audience': audience,
      'dayType': dayType,
      'diet': diet,
      'fasting': fasting,
      'charge': charge,
      'chargeLabel': chargeLabel,
      'effortToday': effort,
      'stepsToday': stepsToday,
      'stepGoal': stepGoal,
      'targetBedtime': targetBedtime,
      'lastNightSleepMin': lastNightSleepMin,
      'usualSleepMin': usualSleepMin,
      'streakDays': streakDays,
      'moveDaysThisWeek': moveDaysThisWeek,
      'proteinTodayG': proteinTodayG,
      'proteinGoalG': proteinGoalG,
      'cyclePhase': cyclePhase,
    };
    m.removeWhere((_, v) => v == null);
    return m;
  }

  /// Plain lines for the "What HUX shares" panel — same facts as [toJson].
  List<String> preview() {
    String hm(int m) => '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
    return [
      if (goals.isNotEmpty) 'Goals: ${goals.join(', ')}',
      if (audience != null) 'For: $audience',
      if (dayType != null) 'Your day: $dayType',
      if (diet != null) 'Diet: $diet',
      if (fasting != null) 'Fasting: $fasting',
      if (charge != null) 'HUX Charge: $charge${chargeLabel != null ? ' ($chargeLabel)' : ''}',
      if (effort != null) "Today's effort: $effort",
      if (stepsToday != null) 'Steps today: $stepsToday${stepGoal != null ? ' of $stepGoal' : ''}',
      if (targetBedtime != null) 'Target bedtime: $targetBedtime',
      if (lastNightSleepMin != null) 'Last night: ${hm(lastNightSleepMin!)} sleep',
      if (usualSleepMin != null) 'Usual sleep: ${hm(usualSleepMin!)}',
      if (streakDays != null) 'Streak: $streakDays days',
      if (moveDaysThisWeek != null) 'Move days this week: $moveDaysThisWeek',
      if (proteinTodayG != null) 'Protein today: $proteinTodayG g${proteinGoalG != null ? ' of $proteinGoalG g' : ''}',
      if (cyclePhase != null) 'Cycle phase: $cyclePhase',
      'Time of day: $partOfDay',
    ];
  }

  static String partOfDayFor(int hour) => hour < 5
      ? 'night'
      : hour < 12
          ? 'morning'
          : hour < 17
              ? 'afternoon'
              : hour < 22
                  ? 'evening'
                  : 'night';
}

/// Gathers [CoachContext] from the app's own services. Each part is
/// optional: if one fails (no data yet), the rest still go.
class CoachContextLoader {
  final HealthStore store;
  final ReadoutService? readouts;
  final ProfileService? profiles;
  final CycleService? cycle;
  final DateTime Function() now;

  CoachContextLoader({required this.store, this.readouts, this.profiles, this.cycle, DateTime Function()? now})
      : now = now ?? DateTime.now;

  Future<CoachContext> load() async {
    final at = now();
    UserProfile? p;
    try {
      p = await profiles?.loadProfile();
    } catch (_) {
      // No profile: coach still works with general advice.
    }

    int? charge, stepsToday, stepGoal;
    String? chargeLabel, effort, bedtime;
    try {
      final r = await readouts?.today(now: at);
      charge = r?.charge?.value;
      chargeLabel = r?.charge?.label;
      effort = r?.plan?.effort?.label;
      stepsToday = r?.plan?.steps?.today;
      stepGoal = r?.plan?.steps?.target;
      final b = r?.plan?.bedtime?.bedtime.toLocal();
      if (b != null) bedtime = _clock(b.hour, b.minute);
    } catch (_) {
      // No readout yet (new user): skip these fields.
    }

    int? lastNight, usual;
    try {
      final utc = at.toUtc();
      final sessions = await store.sleepSessionsBetween(utc.subtract(const Duration(days: 8)), utc);
      final byNight = <DateTime, int>{};
      for (final s in sessions) {
        final k = nightKeyFor(s.bedtime);
        final m = s.totalSleep.inMinutes;
        if (m > (byNight[k] ?? -1)) byNight[k] = m;
      }
      if (byNight.isNotEmpty) {
        final keys = byNight.keys.toList()..sort();
        lastNight = byNight[keys.last];
        if (byNight.length >= 3) {
          final v = byNight.values.toList()..sort();
          usual = v[v.length ~/ 2];
        }
      }
    } catch (_) {
      // Sleep is optional context.
    }

    int? streak, moveDays;
    try {
      final s = await ProgressService(store, now: () => at).streaks();
      streak = s.current;
      moveDays = s.moveDaysThisWeek;
    } catch (_) {
      // Streak is optional context.
    }

    int? protein, proteinGoal;
    try {
      final food = FoodLogService(store);
      if ((await food.mealsFor(at)).isNotEmpty) {
        protein = (await food.totalFor(at)).proteinG.round();
      }
      proteinGoal = (await food.proteinGoal()).round();
    } catch (_) {
      // Food is optional context.
    }

    String? phase;
    try {
      phase = await cycle?.coachPhase();
    } catch (_) {
      // Optional, and off unless the user allowed it.
    }

    return CoachContext(
      goals: [for (final g in p?.goals ?? const <Goal>[]) g.label],
      audience: p?.audience?.label,
      dayType: p?.dayType?.label,
      diet: p?.diet?.label,
      fasting: p?.fasting == null || p!.fasting == FastingHabit.none ? null : p.fasting!.label,
      style: p?.coachStyle,
      language: p?.language,
      partOfDay: CoachContext.partOfDayFor(at.toLocal().hour),
      charge: charge,
      chargeLabel: chargeLabel,
      effort: effort,
      stepsToday: stepsToday,
      stepGoal: stepGoal,
      targetBedtime: bedtime,
      lastNightSleepMin: lastNight,
      usualSleepMin: usual,
      streakDays: streak,
      moveDaysThisWeek: moveDays,
      proteinTodayG: protein,
      proteinGoalG: proteinGoal,
      cyclePhase: phase,
    );
  }

  static String _clock(int h, int m) {
    final hh = h % 12 == 0 ? 12 : h % 12;
    return '$hh:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }
}
