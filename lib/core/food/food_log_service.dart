/// Saves meals per local day, the protein goal, and the user's consent
/// to send meal photos for analysis. Stored on the phone (wiped by
/// "delete my data" and on account switch, like everything else).
library;

import 'dart:convert';

import '../progress/activity_log.dart';
import '../storage/health_store.dart';
import '../trends/night_row.dart';
import 'nutrients.dart';
import 'protein_gap.dart';

class FoodLogService {
  static const _logKey = 'food_log_v1';
  static const _goalKey = 'protein_goal_g';
  static const _weightKey = 'body_weight_kg';

  /// Common adult guide (ICMR-NIN RDA ~0.83 g/kg; WHO 0.8 g/kg).
  static const proteinPerKg = 0.8;
  static const _consentKey = 'food_photo_consent';

  /// Days kept on the phone.
  static const keepDays = 60;

  final HealthStore _store;
  final Duration? _utcOffset;

  FoodLogService(this._store, {Duration? utcOffset}) : _utcOffset = utcOffset;

  DateTime dayKey(DateTime t) => localDayKey(t, utcOffset: _utcOffset);

  Future<Map<DateTime, List<Meal>>> _loadAll() async {
    final raw = await _store.readSetting(_logKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      final result = <DateTime, List<Meal>>{};
      for (final e in decoded.entries) {
        final d = DateTime.tryParse(e.key);
        final list = e.value;
        if (d == null || list is! List) continue;
        final meals = <Meal>[];
        for (final m in list) {
          if (m is! Map<String, Object?>) continue;
          final meal = Meal.fromJson(m);
          if (meal != null) meals.add(meal);
        }
        if (meals.isNotEmpty) result[DateTime.utc(d.year, d.month, d.day)] = meals;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveAll(Map<DateTime, List<Meal>> all, DateTime now) async {
    final cutoff = dayKey(now).subtract(const Duration(days: keepDays));
    all.removeWhere((d, meals) => d.isBefore(cutoff) || meals.isEmpty);
    await _store.writeSetting(
      _logKey,
      jsonEncode({
        for (final e in all.entries)
          _iso(e.key): [for (final m in e.value) m.toJson()],
      }),
    );
  }

  Future<List<Meal>> mealsFor(DateTime day) async => (await _loadAll())[dayKey(day)] ?? const [];

  Future<void> addMeal(Meal meal, {DateTime? now}) async {
    final all = await _loadAll();
    final key = dayKey(meal.loggedAt);
    all[key] = [...?all[key], meal];
    await _saveAll(all, now ?? DateTime.now());
    await ActivityLog(_store, utcOffset: _utcOffset).markDay(key, ActivityKind.meal, now: now);
  }

  /// Days with at least one meal (for streaks).
  Future<Set<DateTime>> daysWithMeals() async =>
      {for (final e in (await _loadAll()).entries) if (e.value.isNotEmpty) e.key};

  Future<void> deleteMeal(DateTime day, int index, {DateTime? now}) async {
    final all = await _loadAll();
    final key = dayKey(day);
    final meals = [...?all[key]];
    if (index < 0 || index >= meals.length) return;
    meals.removeAt(index);
    all[key] = meals;
    await _saveAll(all, now ?? DateTime.now());
    if (meals.isEmpty) {
      await ActivityLog(_store, utcOffset: _utcOffset).markDay(key, ActivityKind.meal, done: false, now: now);
    }
  }

  Future<Nutrients> totalFor(DateTime day) async =>
      (await mealsFor(day)).fold<Nutrients>(Nutrients.zero, (s, m) => s + m.total);

  Future<double> proteinGoal() async {
    final raw = await _store.readSetting(_goalKey);
    final v = raw == null ? null : double.tryParse(raw);
    return (v == null || v <= 0) ? ProteinGap.defaultGoalG.toDouble() : v;
  }

  Future<void> setProteinGoal(double grams) =>
      _store.writeSetting(_goalKey, grams.clamp(20, 250).toString());

  /// Body weight the user entered (kg), or null.
  Future<double?> bodyWeightKg() async {
    final v = double.tryParse(await _store.readSetting(_weightKey) ?? '');
    return v == null || v <= 0 ? null : v;
  }

  /// Saves weight and sets the protein goal from it (0.8 g per kg,
  /// rounded to 5 g). Returns the new goal in grams.
  Future<double> setGoalFromWeight(double kg) async {
    final w = kg.clamp(25, 250).toDouble();
    await _store.writeSetting(_weightKey, w.toStringAsFixed(1));
    final goal = ((w * proteinPerKg) / 5).round() * 5.0;
    await setProteinGoal(goal);
    return goal.clamp(20, 250).toDouble();
  }

  Future<bool> hasPhotoConsent() async => (await _store.readSetting(_consentKey)) == 'yes';

  Future<void> setPhotoConsent(bool yes) => _store.writeSetting(_consentKey, yes ? 'yes' : 'no');

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
