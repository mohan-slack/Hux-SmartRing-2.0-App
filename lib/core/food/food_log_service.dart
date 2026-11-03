/// Saves meals per local day, the protein goal, and the user's consent
/// to send meal photos for analysis. Stored on the phone (wiped by
/// "delete my data" and on account switch, like everything else).
library;

import 'dart:convert';

import '../profile/profile_service.dart';
import '../profile/user_profile.dart';
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

  /// "Your usuals": meals logged the same way on 2+ different days in the
  /// last [days] days, best first — the current meal time's ones lead
  /// (breakfast in the morning). One tap logs them again.
  Future<List<UsualMeal>> usuals({DateTime? now, int max = 3, int days = 30}) async {
    final at = now ?? DateTime.now();
    final from = dayKey(at).subtract(Duration(days: days));
    final byKey = <String, ({Meal sample, Set<DateTime> days, DateTime last})>{};
    for (final e in (await _loadAll()).entries) {
      if (e.key.isBefore(from)) continue;
      for (final m in e.value) {
        if (m.items.isEmpty) continue;
        final key = UsualMeal.signature(m);
        final prev = byKey[key];
        final last = prev == null || m.loggedAt.isAfter(prev.last) ? m.loggedAt : prev.last;
        byKey[key] = (sample: prev?.sample ?? m, days: {...?prev?.days, e.key}, last: last);
      }
    }
    final mealNow = MealTypeLabel.forHour(at.toLocal().hour);
    final list = [
      for (final v in byKey.values)
        if (v.days.length >= 2) UsualMeal(type: v.sample.type, items: v.sample.items, timesLogged: v.days.length, lastLogged: v.last),
    ]..sort((a, b) {
        final first = (b.type == mealNow ? 1 : 0) - (a.type == mealNow ? 1 : 0);
        if (first != 0) return first;
        final c = b.timesLogged.compareTo(a.timesLogged);
        return c != 0 ? c : b.lastLogged.compareTo(a.lastLogged);
      });
    return list.take(max).toList();
  }

  /// Every kept day's meals, keyed by `DateTime.utc(y, m, d)` labels.
  Future<Map<DateTime, List<Meal>>> allMeals() => _loadAll();

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

  /// Grams of protein per kg for this profile's goal, and why.
  ///
  /// - Default 0.8 g/kg: the adult minimum (ICMR-NIN 2020 RDA ~0.83;
  ///   WHO 0.8).
  /// - "Lose weight": 1.0 — more protein helps keep muscle while eating
  ///   less and keeps you fuller.
  /// - "Get fit": 1.2 — regular exercisers (ISSN / ACSM ranges start
  ///   around 1.2–1.4).
  /// - Older adults (retired, "Stay active", a parent's profile): 1.0 —
  ///   PROT-AGE advice for 65+ to slow muscle loss.
  /// - "Sugar & BP" stays at 0.8: higher protein isn't advised without a
  ///   doctor when kidneys may be affected (common with diabetes / BP).
  static ({double perKg, String why}) proteinPerKgFor(UserProfile? p) {
    if (p == null) return (perKg: proteinPerKg, why: 'the adult guide');
    if (p.goals.contains(Goal.sugarBp)) {
      return (perKg: proteinPerKg, why: 'the adult guide — ask your doctor before going higher');
    }
    if (p.goals.contains(Goal.getFit)) return (perKg: 1.2, why: 'for getting fit');
    final older = p.dayType == DayType.retired || p.goals.contains(Goal.activeElder) || p.audience == Audience.parent;
    if (older) return (perKg: 1.0, why: 'to keep muscle strong with age');
    if (p.goals.contains(Goal.loseWeight)) return (perKg: 1.0, why: 'to keep muscle while losing weight');
    return (perKg: proteinPerKg, why: 'the adult guide');
  }

  /// The per-kg rule for the saved profile (see [proteinPerKgFor]).
  Future<({double perKg, String why})> proteinRule() async {
    try {
      return proteinPerKgFor(await ProfileService(_store).loadProfile());
    } catch (_) {
      return proteinPerKgFor(null);
    }
  }

  /// Saves weight and sets the protein goal from it (per kg from the
  /// profile's goal — see [proteinPerKgFor] — rounded to 5 g). Returns
  /// the new goal in grams.
  Future<double> setGoalFromWeight(double kg) async {
    final w = kg.clamp(25, 250).toDouble();
    await _store.writeSetting(_weightKey, w.toStringAsFixed(1));
    final perKg = (await proteinRule()).perKg;
    final goal = ((w * perKg) / 5).round() * 5.0;
    await setProteinGoal(goal);
    return goal.clamp(20, 250).toDouble();
  }

  Future<bool> hasPhotoConsent() async => (await _store.readSetting(_consentKey)) == 'yes';

  Future<void> setPhotoConsent(bool yes) => _store.writeSetting(_consentKey, yes ? 'yes' : 'no');

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// A meal the user logs again and again ("2 roti + dal + curd").
class UsualMeal {
  final MealType type;
  final List<FoodEntry> items;

  /// On how many different days it was logged.
  final int timesLogged;
  final DateTime lastLogged;

  const UsualMeal({required this.type, required this.items, required this.timesLogged, required this.lastLogged});

  /// Same items in the same amounts = the same meal (order doesn't matter).
  static String signature(Meal m) {
    final parts = [
      for (final i in m.items) '${i.quantity}|${i.unit.name}|${(i.foodId ?? i.name).toLowerCase().trim()}',
    ]..sort();
    return parts.join(';');
  }

  /// Short chip text, e.g. "2 roti + dal + curd".
  String get label {
    String one(FoodEntry e) {
      final n = e.name.split('(').first.split('/').first.trim().toLowerCase();
      final q = e.quantity == e.quantity.roundToDouble() ? e.quantity.round().toString() : e.quantity.toString();
      return e.quantity == 1 ? n : '$q $n';
    }

    final names = items.take(3).map(one).join(' + ');
    return items.length > 3 ? '$names +${items.length - 3}' : names;
  }

  Nutrients get total => items.fold(Nutrients.zero, (s, e) => s + e.nutrients);

  /// A new meal with the same items, logged [at] (its meal type follows
  /// the clock, so "your usual breakfast" eaten at 1 PM counts as lunch).
  Meal again(DateTime at) => Meal(type: MealTypeLabel.forHour(at.toLocal().hour), loggedAt: at, items: items);
}
