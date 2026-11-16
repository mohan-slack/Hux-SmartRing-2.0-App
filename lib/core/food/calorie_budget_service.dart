/// Saves the few answers the calorie target needs (sex for the formula,
/// age, activity) and works the target out with the latest weight and
/// height, so it follows your weight as you log it. On the phone only.
library;

import 'dart:convert';

import '../journeys/workout_log.dart';
import '../profile/profile_service.dart';
import '../storage/health_store.dart';
import 'calorie_budget.dart';

class CalorieBudgetService {
  static const _key = 'calorie_inputs_v1';

  final HealthStore _store;
  CalorieBudgetService(this._store);

  WorkoutLog get _body => WorkoutLog(_store);

  /// Saved answers (sex, age, activity), or null before setup.
  Future<({BodySex sex, int age, ActivityLevel activity})?> answers() async {
    try {
      final raw = await _store.readSetting(_key);
      if (raw == null || raw.isEmpty) return null;
      final j = jsonDecode(raw) as Map;
      final sex = BodySex.values.where((s) => s.name == j['sex']).firstOrNull;
      final act = ActivityLevel.values.where((a) => a.name == j['act']).firstOrNull;
      final age = j['age'];
      if (sex == null || act == null || age is! int) return null;
      return (sex: sex, age: age, activity: act);
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    required BodySex sex,
    required int age,
    required ActivityLevel activity,
    required double heightCm,
    required double weightKg,
  }) async {
    await _store.writeSetting(_key, jsonEncode({'sex': sex.name, 'age': age, 'act': activity.name}));
    await _body.setHeightCm(heightCm);
    final last = await _body.latestWeight();
    if (last == null || (last - weightKg).abs() >= 0.1) await _body.addWeight(weightKg);
  }

  Future<void> clear() => _store.writeSetting(_key, '');

  Future<double?> heightCm() => _body.heightCm();
  Future<double?> weightKg() => _body.latestWeight();

  /// Today's target, or null when not set up (or under 18).
  Future<CalorieTarget?> target() async {
    final a = await answers();
    final h = await _body.heightCm();
    final w = await _body.latestWeight();
    if (a == null || h == null || w == null) return null;
    final profile = await ProfileService(_store).loadProfile();
    return CalorieBudget.target(
      BudgetInputs(sex: a.sex, age: a.age, heightCm: h, weightKg: w, activity: a.activity),
      goals: profile?.goals ?? const [],
    );
  }
}
