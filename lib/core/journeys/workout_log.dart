/// Finished workouts, body weight and height — kept ON THE PHONE only.
/// Feeds the "Workout done" screen and the workout Report (weight trend,
/// BMI on the Asian scale, kcal per day). Calories are estimates.
library;

import 'dart:convert';

import '../storage/health_store.dart';
import 'journey_models.dart';

class WorkoutRecord {
  final DateTime at;
  final String title;
  final int moves;
  final int seconds;
  final double kcal;

  const WorkoutRecord({required this.at, required this.title, required this.moves, required this.seconds, required this.kcal});

  Map<String, Object?> toJson() =>
      {'at': at.toUtc().toIso8601String(), 't': title, 'm': moves, 's': seconds, 'k': double.parse(kcal.toStringAsFixed(1))};

  static WorkoutRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse('${j['at']}');
    final m = j['m'], s = j['s'], k = j['k'];
    if (at == null || m is! int || s is! int || k is! num) return null;
    return WorkoutRecord(at: at, title: '${j['t'] ?? 'Workout'}', moves: m, seconds: s, kcal: k.toDouble());
  }
}

class WeightEntry {
  final DateTime at;
  final double kg;
  const WeightEntry(this.at, this.kg);
}

enum BmiBand { under, healthy, over, obese }

extension BmiBandLabel on BmiBand {
  String get label => switch (this) {
        BmiBand.under => 'Underweight',
        BmiBand.healthy => 'Healthy',
        BmiBand.over => 'Overweight',
        BmiBand.obese => 'Obese',
      };
}

/// BMI with the Asian cut-offs used in India (WHO Asia-Pacific / ICMR):
/// healthy 18.5–22.9, overweight 23–24.9, obese 25+.
class Bmi {
  static const cutOffs = [18.5, 23.0, 25.0];

  static double? of({required double? kg, required double? cm}) {
    if (kg == null || cm == null || kg <= 0 || cm < 100 || cm > 230) return null;
    final m = cm / 100;
    return kg / (m * m);
  }

  static BmiBand band(double bmi) => bmi < 18.5
      ? BmiBand.under
      : bmi < 23
          ? BmiBand.healthy
          : bmi < 25
              ? BmiBand.over
              : BmiBand.obese;

  /// Healthy weight range for [cm] on the Asian scale (kg).
  static (double, double) healthyRange(double cm) {
    final m = cm / 100;
    return (18.5 * m * m, 22.9 * m * m);
  }
}

/// Rough calorie estimate: MET × body weight × hours (Compendium of
/// Physical Activities, light-to-moderate home exercise).
class WorkoutKcal {
  static double met(MoveKind k) => switch (k) {
        MoveKind.warmup => 3.0,
        MoveKind.strength => 3.8,
        MoveKind.cardio => 4.0,
        MoveKind.core => 3.0,
        MoveKind.stretch => 2.3,
        MoveKind.breathing => 1.3,
      };

  static double estimate({required Map<MoveKind, int> secondsByKind, required double weightKg}) =>
      secondsByKind.entries.fold<double>(0, (s, e) => s + met(e.key) * weightKg * e.value / 3600);
}

class WorkoutLog {
  static const _key = 'workout_log_v1';
  static const _weightsKey = 'weight_log_v1';
  static const _heightKey = 'body_height_cm';

  /// Same key the food log uses for the protein goal's weight.
  static const _foodWeightKey = 'body_weight_kg';

  /// Used for kcal when the user hasn't entered a weight.
  static const defaultWeightKg = 65.0;
  static const keep = 400;

  final HealthStore _store;
  final DateTime Function() _now;

  WorkoutLog(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  Future<List<WorkoutRecord>> all() async {
    final raw = await _store.readSetting(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).map(WorkoutRecord.fromJson).whereType<WorkoutRecord>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> add(WorkoutRecord r) async {
    final list = [...await all(), r];
    final kept = list.length > keep ? list.sublist(list.length - keep) : list;
    await _store.writeSetting(_key, jsonEncode([for (final w in kept) w.toJson()]));
  }

  Future<List<WeightEntry>> weights() async {
    final raw = await _store.readSetting(_weightsKey);
    final out = <WeightEntry>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final j in jsonDecode(raw) as List) {
          if (j is! Map) continue;
          final at = DateTime.tryParse('${j['at']}');
          final kg = j['kg'];
          if (at != null && kg is num) out.add(WeightEntry(at, kg.toDouble()));
        }
      } catch (_) {}
    }
    // The weight entered for the protein goal counts as a first entry.
    if (out.isEmpty) {
      final kg = double.tryParse(await _store.readSetting(_foodWeightKey) ?? '');
      if (kg != null && kg > 0) out.add(WeightEntry(_now(), kg));
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  /// Adds today's weight (replaces an entry from the same day).
  Future<void> addWeight(double kg) async {
    final w = kg.clamp(25, 250).toDouble();
    final now = _now();
    bool sameDay(DateTime a) {
      final x = a.toLocal(), y = now.toLocal();
      return x.year == y.year && x.month == y.month && x.day == y.day;
    }

    final list = [...await weights()]..removeWhere((e) => sameDay(e.at));
    list.add(WeightEntry(now, w));
    await _store.writeSetting(
        _weightsKey, jsonEncode([for (final e in list) {'at': e.at.toUtc().toIso8601String(), 'kg': e.kg}]));
  }

  Future<double?> latestWeight() async {
    final w = await weights();
    return w.isEmpty ? null : w.last.kg;
  }

  Future<double?> heightCm() async {
    final v = double.tryParse(await _store.readSetting(_heightKey) ?? '');
    return v == null || v < 100 || v > 230 ? null : v;
  }

  Future<void> setHeightCm(double cm) => _store.writeSetting(_heightKey, cm.clamp(100, 230).toStringAsFixed(0));
}
