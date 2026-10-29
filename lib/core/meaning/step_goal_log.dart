/// Remembers the step goal Home actually SHOWED each day, so streaks
/// and the monthly report judge a day against the same number the user
/// saw (Home lowers the goal on rest days and raises it on push days;
/// re-working it later without that effort level disagreed with Home).
library;

import 'dart:convert';

import '../storage/health_store.dart';

class StepGoalLog {
  static const _key = 'step_goals_shown_v1';

  /// Goals older than this are dropped (streaks look back less).
  static const keepDays = 120;

  final HealthStore _store;
  const StepGoalLog(this._store);

  static String dayKey(DateTime localDay) =>
      '${localDay.year.toString().padLeft(4, '0')}-'
      '${localDay.month.toString().padLeft(2, '0')}-'
      '${localDay.day.toString().padLeft(2, '0')}';

  Future<Map<String, int>> loadAll() async {
    try {
      final raw = await _store.readSetting(_key);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.value is num) e.key.toString(): (e.value as num).round(),
      };
    } catch (_) {
      return {};
    }
  }

  /// Records [goal] for [localDay] (year/month/day are used as-is).
  Future<void> record(DateTime localDay, int goal) async {
    final all = await loadAll();
    final key = dayKey(localDay);
    if (all[key] == goal) return;
    all[key] = goal;
    final cutoff = dayKey(DateTime(localDay.year, localDay.month, localDay.day - keepDays));
    all.removeWhere((k, _) => k.compareTo(cutoff) < 0);
    await _store.writeSetting(_key, jsonEncode(all));
  }

  /// The goal shown on [localDay], or null if Home never showed one.
  Future<int?> goalFor(DateTime localDay) async => (await loadAll())[dayKey(localDay)];
}
