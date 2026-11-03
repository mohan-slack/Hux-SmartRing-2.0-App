/// Which app sent which data: Apple Health / Health Connect tag every
/// reading with the app that wrote it. HUX keeps a small summary per
/// kind of data (who sent it, when last) so a user can see at a glance
/// "steps ✓ from AIZO RING, sleep ✗ — nothing sends it" instead of
/// digging through phone settings. Plus daily walking distance, which
/// only this summary stores. On the phone only.
library;

import 'dart:convert';

import '../storage/health_store.dart';

enum HealthKind { sleep, heartRate, hrv, spo2, breathing, steps, activeEnergy, distance }

extension HealthKindInfo on HealthKind {
  String get label => switch (this) {
        HealthKind.sleep => 'Sleep',
        HealthKind.heartRate => 'Heart rate',
        HealthKind.hrv => 'HRV',
        HealthKind.spo2 => 'Blood oxygen',
        HealthKind.breathing => 'Breathing rate',
        HealthKind.steps => 'Steps',
        HealthKind.activeEnergy => 'Active calories',
        HealthKind.distance => 'Walking distance',
      };

  /// What HUX does with it, or does instead when it's missing.
  String get usedFor => switch (this) {
        HealthKind.sleep => 'Last night, Charge, bedtime plan. Without it: the morning check-in.',
        HealthKind.heartRate => 'Resting heart and Charge. Without it: Charge uses sleep only.',
        HealthKind.hrv => 'Recovery in Charge. Without it: sleep and heart rate.',
        HealthKind.spo2 => 'Shown on Last night.',
        HealthKind.breathing => 'Shown on Last night; a small recovery signal.',
        HealthKind.steps => 'Step goal, Move score, streaks.',
        HealthKind.activeEnergy => 'Shown with steps.',
        HealthKind.distance => 'Shown with steps.',
      };
}

class KindSources {
  /// Apps/devices that sent it (display names), most data first.
  final List<String> sources;
  final DateTime? last;
  const KindSources(this.sources, this.last);

  bool get received => sources.isNotEmpty;

  Map<String, Object?> toJson() => {'s': sources, if (last != null) 'l': last!.toUtc().toIso8601String()};
  static KindSources fromJson(Object? j) {
    if (j is! Map) return const KindSources([], null);
    final s = j['s'];
    return KindSources(
      s is List ? [for (final x in s) if (x is String) x] : const [],
      DateTime.tryParse('${j['l']}'),
    );
  }
}

class HealthSourceReport {
  final Map<HealthKind, KindSources> kinds;

  /// Walking distance per local day ("yyyy-mm-dd" → metres).
  final Map<String, double> distanceByDay;
  final DateTime? checkedAt;

  const HealthSourceReport({this.kinds = const {}, this.distanceByDay = const {}, this.checkedAt});

  static const empty = HealthSourceReport();

  KindSources of(HealthKind k) => kinds[k] ?? const KindSources([], null);

  static String dayKey(DateTime local) =>
      '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';

  double? distanceOn(DateTime local) => distanceByDay[dayKey(local)];

  /// Newer sync on top of what we knew: a kind with no readings in the
  /// new window keeps its old sources (it may just not have new data).
  HealthSourceReport mergedWith(HealthSourceReport newer, {int keepDays = 30}) {
    final kinds = {...this.kinds};
    newer.kinds.forEach((k, v) {
      if (v.received) kinds[k] = v;
    });
    final days = {...distanceByDay, ...newer.distanceByDay};
    final keys = days.keys.toList()..sort();
    if (keys.length > keepDays) {
      for (final k in keys.take(keys.length - keepDays)) {
        days.remove(k);
      }
    }
    return HealthSourceReport(kinds: kinds, distanceByDay: days, checkedAt: newer.checkedAt ?? checkedAt);
  }

  Map<String, Object?> toJson() => {
        'k': {for (final e in kinds.entries) e.key.name: e.value.toJson()},
        'd': distanceByDay,
        if (checkedAt != null) 'at': checkedAt!.toUtc().toIso8601String(),
      };

  static HealthSourceReport fromJson(Object? j) {
    if (j is! Map) return empty;
    final k = j['k'], d = j['d'];
    return HealthSourceReport(
      kinds: {
        if (k is Map)
          for (final kind in HealthKind.values)
            if (k[kind.name] != null) kind: KindSources.fromJson(k[kind.name]),
      },
      distanceByDay: {
        if (d is Map)
          for (final e in d.entries)
            if (e.key is String && e.value is num) e.key as String: (e.value as num).toDouble(),
      },
      checkedAt: DateTime.tryParse('${j['at']}'),
    );
  }

  /// Android reports the app's package name; show people a real name.
  static String friendlySource(String raw) {
    const known = {
      'com.google.android.apps.fitness': 'Google Fit',
      'com.google.android.apps.healthdata': 'Health Connect',
      'com.sec.android.app.shealth': 'Samsung Health',
      'com.ouraring.oura': 'Oura',
      'com.fitbit.FitbitMobile': 'Fitbit',
      'com.xiaomi.wearable': 'Mi Fitness',
      'com.mi.health': 'Mi Fitness',
      'com.huami.watch.hmwatchmanager': 'Zepp',
      'com.garmin.android.apps.connectmobile': 'Garmin Connect',
      'com.whoop.android': 'WHOOP',
      'com.eiot.be.ring': 'AIZO RING',
      'com.nothing.smartcenter': 'Nothing X',
      'com.noisefit': 'NoiseFit',
    };
    final t = raw.trim();
    if (known.containsKey(t)) return known[t]!;
    if (!t.contains('.') || t.contains(' ')) return t; // already a name (iOS)
    // Unknown package: last part, capitalised ("com.acme.bandfit" → "Bandfit").
    final last = t.split('.').last;
    return last.isEmpty ? t : '${last[0].toUpperCase()}${last.substring(1)}';
  }
}

class HealthSourcesStore {
  static const _key = 'health_sources_v1';
  final HealthStore _store;
  HealthSourcesStore(this._store);

  Future<HealthSourceReport> load() async {
    try {
      final raw = await _store.readSetting(_key);
      return raw == null || raw.isEmpty ? HealthSourceReport.empty : HealthSourceReport.fromJson(jsonDecode(raw));
    } catch (_) {
      return HealthSourceReport.empty;
    }
  }

  Future<void> add(HealthSourceReport newer) async =>
      _store.writeSetting(_key, jsonEncode((await load()).mergedWith(newer).toJson()));
}
