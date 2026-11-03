/// Loads what [WeekScoreCalculator] needs from the phone's store.
/// Shared by Progress → Score and the coach's weekly check-in.
library;

import '../checkin/sleep_checkin.dart';
import '../food/food_log_service.dart';
import '../storage/health_store.dart';
import 'goal_score.dart';
import 'progress_service.dart';

Future<WeekScore> loadWeekScore(HealthStore store, ProgressService progress, {DateTime? now}) async {
  final at = now ?? DateTime.now();
  final today = progress.today();
  final utc = at.toUtc();
  final sessions = await SleepCheckInService.nightsBetween(store, utc.subtract(const Duration(days: 30)), utc);
  final records = await progress.records(today.subtract(const Duration(days: 15)));
  final food = FoodLogService(store);
  return const WeekScoreCalculator().calculate(
    today: today,
    sessions: sessions,
    records: records,
    mealsByDay: await food.allMeals(),
    proteinGoalG: await food.proteinGoal(),
  );
}
