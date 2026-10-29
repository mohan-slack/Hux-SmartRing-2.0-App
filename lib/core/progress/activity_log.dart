/// Which healthy actions happened on which local day: a guided session,
/// a meal logged, a journal entry. Small (one short list per day), kept
/// for [keepDays] so streaks and monthly reports outlive the food log
/// (60 days) and the journal (120 days).
///
/// Steps are NOT stored here — they come straight from the health store.
library;

import 'dart:convert';

import '../storage/health_store.dart';
import '../trends/night_row.dart';

enum ActivityKind { planSession, meal, journal }

class ActivityLog {
  static const _key = 'activity_days_v1';
  static const keepDays = 400;

  final HealthStore _store;
  final Duration? _utcOffset;

  /// [utcOffset] is for tests; null = the device's own timezone.
  ActivityLog(this._store, {Duration? utcOffset}) : _utcOffset = utcOffset;

  Future<Map<DateTime, Set<ActivityKind>>> loadAll() async {
    final raw = await _store.readSetting(_key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      final out = <DateTime, Set<ActivityKind>>{};
      for (final e in decoded.entries) {
        final day = DateTime.tryParse(e.key);
        final list = e.value;
        if (day == null || list is! List) continue;
        final kinds = {
          for (final k in ActivityKind.values)
            if (list.contains(k.name)) k,
        };
        if (kinds.isNotEmpty) out[DateTime.utc(day.year, day.month, day.day)] = kinds;
      }
      return out;
    } catch (_) {
      return {}; // Corrupt setting: start fresh rather than crash.
    }
  }

  /// Records [kind] on the local day of the instant [at].
  Future<void> mark(DateTime at, ActivityKind kind, {bool done = true, DateTime? now}) =>
      markDay(localDayKey(at, utcOffset: _utcOffset), kind, done: done, now: now);

  /// Records [kind] on [dayKey], a `DateTime.utc(y, m, d)` day label
  /// (the same labels the journal and food log use).
  Future<void> markDay(DateTime dayKey, ActivityKind kind, {bool done = true, DateTime? now}) async {
    final all = await loadAll();
    final day = DateTime.utc(dayKey.year, dayKey.month, dayKey.day);
    final kinds = {...?all[day]};
    final changed = done ? kinds.add(kind) : kinds.remove(kind);
    if (!changed) return;
    if (kinds.isEmpty) {
      all.remove(day);
    } else {
      all[day] = kinds;
    }
    await _save(all, now ?? DateTime.now());
  }

  /// Adds days found elsewhere (e.g. journal entries saved before this
  /// log existed). Never removes anything.
  Future<void> backfill(Map<DateTime, Set<ActivityKind>> found, {DateTime? now}) async {
    final all = await loadAll();
    var changed = false;
    for (final e in found.entries) {
      final day = DateTime.utc(e.key.year, e.key.month, e.key.day);
      final kinds = all[day] ?? <ActivityKind>{};
      for (final k in e.value) {
        if (kinds.add(k)) changed = true;
      }
      if (kinds.isNotEmpty) all[day] = kinds;
    }
    if (changed) await _save(all, now ?? DateTime.now());
  }

  Future<void> _save(Map<DateTime, Set<ActivityKind>> all, DateTime now) {
    final cutoff = localDayKey(now, utcOffset: _utcOffset).subtract(const Duration(days: keepDays));
    all.removeWhere((d, _) => d.isBefore(cutoff));
    return _store.writeSetting(
      _key,
      jsonEncode({
        for (final e in all.entries) _iso(e.key): [for (final k in e.value) k.name],
      }),
    );
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
