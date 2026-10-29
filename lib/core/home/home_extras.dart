/// Everything the richer Home needs beyond the daily readout: a timed
/// agenda, today's food totals, and 7-day sleep/steps mini trends.
/// Every source is optional — if one fails or isn't set up, the rest
/// still show (Home must never break because, say, the weather is down).
library;

import '../environment/environment_service.dart';
import '../food/food_log_service.dart';
import '../journal/journal.dart';
import '../meaning/step_target.dart';
import '../nudges/nudge_planner.dart';
import '../nudges/nudge_service.dart';
import '../plans/plan_progress.dart';
import '../profile/feature_catalog.dart';
import '../storage/health_store.dart';
import '../trends/night_row.dart';

enum AgendaKind { air, walk, plan, journal }

class AgendaEntry {
  /// Minutes since local midnight (for ordering and "past" styling).
  final int minuteOfDay;
  final String time;
  final AgendaKind kind;
  final String title;
  final String? detail;
  final bool done;

  /// What a tap opens.
  final FeatureId? feature;

  const AgendaEntry({
    required this.minuteOfDay,
    required this.time,
    required this.kind,
    required this.title,
    this.detail,
    this.done = false,
    this.feature,
  });
}

class FoodToday {
  final int meals;
  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double proteinGoalG;

  const FoodToday({
    required this.meals,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.proteinGoalG,
  });
}

class HomeExtras {
  final List<AgendaEntry> agenda;
  final FoodToday? food;

  /// Last 7 nights' sleep in minutes, oldest first (null = no data).
  final List<int?> sleep7;

  /// Last 7 days' steps including today, oldest first.
  final List<int?> steps7;

  const HomeExtras({
    this.agenda = const [],
    this.food,
    this.sleep7 = const [],
    this.steps7 = const [],
  });

  static const empty = HomeExtras();
}

class HomeExtrasLoader {
  final HealthStore store;
  final FoodLogService? foodLog;
  final NudgeService? nudges;
  final EnvironmentService? environment;
  final PlanProgressService? plans;
  final JournalService? journal;
  final DateTime Function() now;

  HomeExtrasLoader({
    required this.store,
    this.foodLog,
    this.nudges,
    this.environment,
    this.plans,
    this.journal,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  // One weather/air fetch per hour is plenty for Home.
  static ({DateTime at, String city, Outlooks outlooks})? _airCache;

  static String _clock(int minuteOfDay) => TimeOfDayHm(minuteOfDay ~/ 60, minuteOfDay % 60).label;

  Future<HomeExtras> load() async {
    final at = now();
    final agenda = <AgendaEntry>[];

    // Best time to walk (air & heat), when a city is set.
    try {
      final env = environment;
      final city = await env?.city();
      if (env != null && city != null) {
        final cached = _airCache;
        final Outlooks o;
        if (cached != null && cached.city == city.name && at.difference(cached.at).inMinutes < 60) {
          o = cached.outlooks;
        } else {
          o = await env.outlooks(city);
          _airCache = (at: at, city: city.name, outlooks: o);
        }
        final walk = o.today.bestWalk;
        if (walk != null) {
          agenda.add(AgendaEntry(
            minuteOfDay: walk.startHour * 60,
            time: _clock(walk.startHour * 60),
            kind: AgendaKind.air,
            title: 'Best time to walk',
            detail: '${walk.label} in ${city.name}',
            feature: FeatureId.airAndHeatAlerts,
          ));
        } else if (o.today.alertWorthy) {
          agenda.add(AgendaEntry(
            minuteOfDay: 7 * 60,
            time: _clock(7 * 60),
            kind: AgendaKind.air,
            title: 'Move workouts indoors today',
            detail: o.today.advice,
            feature: FeatureId.airAndHeatAlerts,
          ));
        }
      }
    } catch (_) {
      // Weather is a bonus; never block Home on it.
    }

    // Walks after lunch and dinner (your reminder times, or suggestions).
    try {
      final s = await nudges?.walkSettings() ?? WalkNudgeSettings.defaults;
      final on = s.enabled;
      final times = on
          ? [for (final n in const NudgePlanner().dailyWalkNudges(s)) (at: n.at, title: n.title)]
          : [
              (at: s.lunch.plusMinutes(20), title: '10-min walk after lunch'),
              (at: s.dinner.plusMinutes(20), title: '10-min walk after dinner'),
            ];
      for (final t in times) {
        agenda.add(AgendaEntry(
          minuteOfDay: t.at.minutesOfDay,
          time: t.at.label,
          kind: AgendaKind.walk,
          title: t.title,
          detail: on ? 'Reminder on' : 'Helps your sugar after meals · tap to set a reminder',
          feature: FeatureId.walkAfterMeal,
        ));
      }
    } catch (_) {
      // Optional.
    }

    // The next session of a plan you've started.
    try {
      final all = await plans?.allProgress() ?? const {};
      for (final p in all.values) {
        final plan = p.plan;
        final next = p.nextIndex;
        if (plan == null || next == null || p.completed.isEmpty) continue;
        final session = plan.sessions[next];
        agenda.add(AgendaEntry(
          minuteOfDay: 18 * 60,
          time: _clock(18 * 60),
          kind: AgendaKind.plan,
          title: '${plan.name}: week ${session.week}, day ${session.day}',
          detail: '${session.minutes} min guided session',
          feature: FeatureId.beginnerWalkPlan,
        ));
        break;
      }
    } catch (_) {
      // Optional.
    }

    // Evening journal.
    try {
      final j = journal;
      if (j != null) {
        final logged = (await j.tagsFor(at)).isNotEmpty;
        agenda.add(AgendaEntry(
          minuteOfDay: 21 * 60 + 30,
          time: _clock(21 * 60 + 30),
          kind: AgendaKind.journal,
          title: logged ? 'Journal done for today' : 'Journal today',
          detail: logged ? null : 'Chai, late dinner, sweets — 10 seconds',
          done: logged,
          feature: FeatureId.indianJournal,
        ));
      }
    } catch (_) {
      // Optional.
    }

    agenda.sort((a, b) => a.minuteOfDay.compareTo(b.minuteOfDay));

    // Food today.
    FoodToday? food;
    try {
      final f = foodLog;
      if (f != null) {
        final meals = await f.mealsFor(at);
        final t = await f.totalFor(at);
        food = FoodToday(
          meals: meals.length,
          kcal: t.kcal,
          proteinG: t.proteinG,
          carbsG: t.carbsG,
          fatG: t.fatG,
          proteinGoalG: await f.proteinGoal(),
        );
      }
    } catch (_) {
      // Optional.
    }

    // 7-day mini trends.
    var sleep7 = <int?>[];
    var steps7 = <int?>[];
    try {
      final utc = at.toUtc();
      final today = localDayKey(at);
      final sessions = await store.sleepSessionsBetween(utc.subtract(const Duration(days: 9)), utc);
      final byNight = <DateTime, int>{};
      for (final s in sessions) {
        final k = nightKeyFor(s.bedtime);
        final m = s.totalSleep.inMinutes;
        if (m > (byNight[k] ?? -1)) byNight[k] = m;
      }
      // Nights ending this morning: night keys today-7 .. today-1.
      sleep7 = [for (var i = 7; i >= 1; i--) byNight[today.subtract(Duration(days: i))]];

      final snaps = await store.snapshotsBetween(utc.subtract(const Duration(days: 8)), utc.add(const Duration(minutes: 1)));
      final totals = StepTargetCalculator.dailyTotals(snaps);
      steps7 = [for (var i = 6; i >= 0; i--) totals[today.subtract(Duration(days: i))]];
    } catch (_) {
      // Optional.
    }

    return HomeExtras(agenda: agenda, food: food, sleep7: sleep7, steps7: steps7);
  }
}
