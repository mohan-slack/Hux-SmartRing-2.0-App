/// Water: one tap per glass (250 ml), a goal that grows on hot days.
///
/// Goal: about 30 ml per kg of body weight (8 glasses when weight isn't
/// known), kept between 6 and 12 glasses; +2 on a hot day, +3 in a
/// heatwave. A general guide for healthy adults, not medical advice —
/// people told to limit fluids should follow their doctor.
///
/// Stored on the phone only.
library;

import 'dart:convert';

import '../environment/outlook.dart';
import '../storage/health_store.dart';

class WaterGoal {
  /// Glasses for today.
  final int glasses;

  /// Plain words: why this number (shown under the tile on hot days).
  final String? why;

  const WaterGoal(this.glasses, {this.why});

  static const glassMl = 250;
  static const defaultGlasses = 8;
  static const minGlasses = 6;
  static const maxGlasses = 12;

  static WaterGoal of({double? weightKg, HeatLevel heat = HeatLevel.none}) {
    final base = weightKg == null || weightKg < 30 || weightKg > 250
        ? defaultGlasses
        : (weightKg * 30 / glassMl).round().clamp(minGlasses, maxGlasses);
    return switch (heat) {
      HeatLevel.none => WaterGoal(base),
      HeatLevel.caution => WaterGoal(base + 2, why: 'Hot day: 2 extra glasses'),
      HeatLevel.heatwave || HeatLevel.severe => WaterGoal(base + 3, why: 'Heatwave: 3 extra glasses, sip often'),
    };
  }
}

class WaterLog {
  static const _key = 'water_v1';
  static const keepDays = 60;

  /// More taps than this in a day are ignored (a stuck finger, a toddler).
  static const maxPerDay = 30;

  final HealthStore _store;
  final DateTime Function() _now;

  WaterLog(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  static String dayKey(DateTime d) {
    final l = d.toLocal();
    return '${l.year.toString().padLeft(4, '0')}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

  Future<Map<String, int>> _load() async {
    try {
      final raw = await _store.readSetting(_key);
      if (raw == null || raw.isEmpty) return {};
      return {
        for (final e in (jsonDecode(raw) as Map).entries)
          if (e.value is int && e.value as int > 0) e.key.toString(): e.value as int,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(Map<String, int> all) async {
    final keys = all.keys.toList()..sort();
    final keep = keys.length > keepDays ? keys.sublist(keys.length - keepDays) : keys;
    await _store.writeSetting(_key, jsonEncode({for (final k in keep) k: all[k]}));
  }

  /// Glasses logged today.
  Future<int> today() async => (await _load())[dayKey(_now())] ?? 0;

  /// Adds [delta] glasses (negative = undo). Returns today's new count.
  Future<int> add([int delta = 1]) async {
    final all = await _load();
    final k = dayKey(_now());
    final next = ((all[k] ?? 0) + delta).clamp(0, maxPerDay);
    if (next == 0) {
      all.remove(k);
    } else {
      all[k] = next;
    }
    await _save(all);
    return next;
  }

  /// Last [days] days including today, oldest first (0 = nothing logged).
  Future<List<int>> lastDays([int days = 7]) async {
    final all = await _load();
    final now = _now().toLocal();
    return [
      for (var i = days - 1; i >= 0; i--) all[dayKey(DateTime(now.year, now.month, now.day - i))] ?? 0,
    ];
  }
}

/// What Home shows.
class WaterToday {
  final int glasses;
  final WaterGoal goal;

  const WaterToday({required this.glasses, required this.goal});
}
