/// Reads past period days from Apple Health / Health Connect.
///
/// READ-ONLY, and asked for only when the user taps "Import from
/// Health" in Cycle — never as part of the main health permission.
library;

import 'package:health/health.dart' as hk;

/// Where past bleeding days come from (fake in tests).
abstract class CyclePeriodSource {
  /// Local days with period bleeding (not spotting) in [from, to].
  Future<List<DateTime>> bleedingDays(DateTime from, DateTime to);
}

class CycleImportDenied implements Exception {
  const CycleImportDenied();
}

class HealthCycleSource implements CyclePeriodSource {
  hk.Health? _h;

  /// Created on first import only — nothing touches Health until then.
  hk.Health get _health => _h ??= hk.Health();

  HealthCycleSource({hk.Health? health}) : _h = health;

  static const _types = [hk.HealthDataType.MENSTRUATION_FLOW];

  @override
  Future<List<DateTime>> bleedingDays(DateTime from, DateTime to) async {
    await _health.configure();
    final ok = await _health.requestAuthorization(_types, permissions: const [hk.HealthDataAccess.READ]);
    if (!ok) throw const CycleImportDenied();
    final points = await _health.getHealthDataFromTypes(types: _types, startTime: from, endTime: to);
    final out = <DateTime>[];
    for (final p in points) {
      final flow = _flow(p);
      if (flow == 'none' || flow == 'spotting') continue;
      final t = p.dateFrom.toLocal();
      out.add(DateTime(t.year, t.month, t.day));
    }
    return out;
  }

  /// The flow name ("light", "medium", "heavy", "unspecified", "none",
  /// "spotting"), read defensively: the value type differs by platform.
  static String? _flow(hk.HealthDataPoint p) {
    try {
      final json = (p.value as dynamic).toJson() as Map;
      final f = json['flow'];
      if (f == null) return null;
      return f.toString().split('.').last.toLowerCase();
    } catch (_) {
      return null;
    }
  }
}
