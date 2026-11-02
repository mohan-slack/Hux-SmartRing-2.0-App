/// "Coach noticed" patterns, low-impact swaps, week score, workout log.
/// Run with: flutter test test/coach_nudges_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/coach/coach_context.dart';
import 'package:hux_app/core/coach/coach_nudges.dart';
import 'package:hux_app/core/coach/coach_service.dart';
import 'package:hux_app/core/food/nutrients.dart';
import 'package:hux_app/core/home/home_insights.dart';
import 'package:hux_app/core/journeys/journey_content.dart';
import 'package:hux_app/core/journeys/journey_models.dart';
import 'package:hux_app/core/journeys/workout_log.dart';
import 'package:hux_app/core/progress/goal_score.dart';
import 'package:hux_app/core/progress/streaks.dart';
import 'package:hux_app/core/ring/ring_models.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final today = DateTime.utc(2026, 11, 2);

Meal meal(MealType t, DateTime day, {int hour = 13, double protein = 10}) => Meal(
      type: t,
      loggedAt: DateTime(day.year, day.month, day.day, hour),
      items: [
        FoodEntry(
          name: 'x',
          foodId: null,
          quantity: 1,
          unit: FoodUnit.piece,
          nutrients: Nutrients(kcal: 200, proteinG: protein, carbsG: 20, fatG: 5),
          source: NutrientSource.database,
        ),
      ],
    );

DateTime ago(int d) => today.subtract(Duration(days: d));

void main() {
  sqfliteFfiInit();

  group('CoachNudges', () {
    test('notices a skipped lunch and offers to log it', () {
      final meals = {
        for (var d = 1; d <= 6; d++) ago(d): [meal(MealType.breakfast, ago(d), hour: 9), meal(MealType.dinner, ago(d), hour: 20)],
      };
      meals[ago(3)] = [...meals[ago(3)]!, meal(MealType.lunch, ago(3))];
      final n = CoachNudges.pick(mealsByDay: meals, today: today, proteinGoalG: 20)!;
      expect(n.id, 'skip_lunch');
      expect(n.topic, CoachTopic.food);
      expect(n.headline, 'You log breakfast and dinner, rarely lunch');
      expect(n.action, CoachNudgeAction.logMeal);
      expect(n.meal, MealType.lunch);
    });

    test('hidden ids are skipped; nothing when there is no pattern', () {
      final meals = {
        for (var d = 1; d <= 6; d++) ago(d): [meal(MealType.breakfast, ago(d), hour: 9), meal(MealType.dinner, ago(d), hour: 20)],
      };
      expect(CoachNudges.pick(mealsByDay: meals, today: today, hidden: {'skip_lunch'}, proteinGoalG: 20), isNull);
      expect(CoachNudges.pick(mealsByDay: const {}, today: today), isNull);
    });

    test('three short nights come first', () {
      final n = CoachNudges.pick(mealsByDay: const {}, today: today, sleep7: [420, 430, 410, 400, 300, 320, 310]);
      expect(n?.id, 'short_nights');
      expect(n?.topic, CoachTopic.sleep);
    });

    test('bedtime drift and steady bedtime', () {
      NightWindow at(int h, int m) {
        final bed = DateTime(2026, 10, 30, h, m);
        return NightWindow(bed: bed, wake: bed.add(const Duration(hours: 7)), asleepMinutes: 420);
      }

      final drift = CoachNudges.pick(
          mealsByDay: const {}, today: today, nights7: [at(22, 30), at(22, 40), at(22, 30), at(23, 50), at(23, 40), at(23, 55)]);
      expect(drift?.id, 'bedtime_drift');
      expect(drift?.headline, contains('later'));

      final steady = CoachNudges.pick(
          mealsByDay: const {}, today: today, nights7: [at(22, 30), at(22, 40), at(22, 30), at(22, 50), at(22, 35)]);
      expect(steady?.id, 'steady_bedtime');
      expect(steady?.positive, isTrue);
    });

    test('steps dip ignores today', () {
      final n = CoachNudges.pick(mealsByDay: const {}, today: today, steps7: [6000, 6500, 6200, 2000, 2400, 1800, 100]);
      expect(n?.id, 'steps_drop');
      expect(n?.topic, CoachTopic.move);
    });

    test('store hides for 3 days', () async {
      final store = await SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);
      var now = DateTime(2026, 11, 2, 9);
      final s = CoachNudgeStore(store, now: () => now);
      await s.hide('skip_lunch');
      expect(await s.hidden(), {'skip_lunch'});
      now = now.add(const Duration(days: 3));
      expect(await s.hidden(), isEmpty);
      await store.close();
    });
  });

  group('low impact', () {
    test('swaps jumping and knee-heavy moves, keeps timing', () {
      final day = journeyDay(JourneyId.fitIn30, 1, FitnessLevel.regular);
      expect(hasHighImpact(day.workout), isTrue);
      final low = lowImpactVersion(day.workout);
      expect(hasHighImpact(low), isFalse);
      expect(low.minutes, day.workout.minutes);
      expect(low.allSteps.any((s) => s.moveId == 'step_jacks'), isFalse);
      for (final id in lowImpactSwaps.values) {
        expect(() => moveById(id), returnsNormally);
      }
    });
  });

  group('WeekScore', () {
    test('parts with data average into the week score', () {
      final sessions = [
        for (var d = 1; d <= 14; d++)
          SleepSession(
            bedtime: DateTime(2026, 11, 2 - d, 22, 30),
            wakeTime: DateTime(2026, 11, 3 - d, 6, 0),
            segments: [
              SleepSegment(
                  start: DateTime(2026, 11, 2 - d, 22, 30), end: DateTime(2026, 11, 3 - d, 6, 0), stage: SleepStage.light),
            ],
            avgHrvMs: 50,
            avgHeartRateBpm: 60,
          ),
      ];
      final records = {
        for (var d = 1; d <= 7; d++) ago(d): DayRecord(day: ago(d), steps: d.isEven ? 8000 : 4000, stepGoal: 8000),
      };
      final w = const WeekScoreCalculator().calculate(
        today: today,
        sessions: sessions,
        records: records,
        mealsByDay: {ago(1): [meal(MealType.lunch, ago(1), protein: 50)]},
        proteinGoalG: 50,
      );
      expect(w.parts[ScorePart.sleep]!.score, 100); // 7.5 h, same bedtime
      expect(w.parts[ScorePart.energy]!.score, 50); // exactly usual
      expect(w.parts[ScorePart.move]!.score, 71); // 3×1.0 + 4×0.5 over 7
      expect(w.parts[ScorePart.food]!.score, 14); // 1 day of 7
      expect(w.overall, ((100 + 50 + 71 + 14) / 4).round());
      expect(w.contributions.values.fold<double>(0, (a, b) => a + b), closeTo(w.overall!, 1));
    });

    test('no data = no score, not zero', () {
      final w = const WeekScoreCalculator()
          .calculate(today: today, sessions: const [], records: const {}, mealsByDay: const {}, proteinGoalG: 50);
      expect(w.overall, isNull);
      expect(w.contributions, isEmpty);
    });
  });

  group('WorkoutLog', () {
    test('records, weights, height and BMI (Asian cut-offs)', () async {
      final store = await SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);
      final log = WorkoutLog(store, now: () => DateTime(2026, 11, 2, 8));
      await log.add(WorkoutRecord(at: DateTime(2026, 11, 2, 7), title: 'Push & core', moves: 12, seconds: 900, kcal: 80));
      expect((await log.all()).single.title, 'Push & core');
      await log.addWeight(72.4);
      await log.addWeight(72.0); // same day replaces
      expect((await log.weights()).single.kg, 72.0);
      await log.setHeightCm(170);
      final bmi = Bmi.of(kg: await log.latestWeight(), cm: await log.heightCm())!;
      expect(bmi, closeTo(24.9, 0.1));
      expect(Bmi.band(bmi), BmiBand.over); // 23–24.9 on the Asian scale
      expect(Bmi.band(22.9), BmiBand.healthy);
      expect(Bmi.band(25), BmiBand.obese);
      await store.close();
    });

    test('kcal estimate uses MET × weight × time', () {
      final k = WorkoutKcal.estimate(secondsByKind: {MoveKind.strength: 600}, weightKg: 60);
      expect(k, closeTo(3.8 * 60 * 600 / 3600, 0.01)); // 38 kcal
    });
  });

  group('CoachService topics', () {
    test('each specialist keeps its own chat and sends its topic', () async {
      final store = await SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);
      final bodies = <Map<String, Object?>>[];
      final svc = CoachService(
        store,
        invoke: (name, body) async {
          bodies.add(body);
          return {'reply': 'ok'};
        },
        loadContext: () async => const CoachContext(partOfDay: 'morning'),
      );
      await svc.giveConsent();
      await svc.send('hi');
      await svc.send('why do I wake up tired?', topic: CoachTopic.sleep);
      expect(bodies[0].containsKey('topic'), isFalse); // general = original chat
      expect(bodies[1]['topic'], 'sleep');
      expect((await svc.history()).length, 2);
      expect((await svc.history(topic: CoachTopic.sleep)).first.text, 'why do I wake up tired?');
      expect((await svc.lastMessages())[CoachTopic.food], isNull);
      await svc.clearHistory(topic: CoachTopic.sleep);
      expect(await svc.history(topic: CoachTopic.sleep), isEmpty);
      expect(await svc.history(), hasLength(2));
      await svc.withdrawConsent(); // clears every chat
      expect(await svc.history(), isEmpty);
      await store.close();
    });
  });
}
