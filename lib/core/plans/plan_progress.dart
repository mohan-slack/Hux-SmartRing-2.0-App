/// Which plan is active and which sessions are done. Stored on the phone.
library;

import 'dart:convert';

import '../progress/activity_log.dart';
import '../storage/health_store.dart';
import 'plan_library.dart';
import 'plan_models.dart';

class PlanProgress {
  final String planId;

  /// Indexes into the plan's session list that are complete.
  final Set<int> completed;
  final bool readinessConfirmed;

  const PlanProgress({required this.planId, required this.completed, required this.readinessConfirmed});

  Plan? get plan => planById(planId);

  /// The next session to do (first not completed), or null when finished.
  int? get nextIndex {
    final p = plan;
    if (p == null) return null;
    for (var i = 0; i < p.sessions.length; i++) {
      if (!completed.contains(i)) return i;
    }
    return null;
  }

  double get fraction {
    final p = plan;
    if (p == null || p.sessions.isEmpty) return 0;
    return completed.length / p.sessions.length;
  }
}

class PlanProgressService {
  static const _key = 'plan_progress_v1';

  final HealthStore _store;
  final Duration? _utcOffset;

  /// [utcOffset] is for tests; null = the device's own timezone.
  PlanProgressService(this._store, {Duration? utcOffset}) : _utcOffset = utcOffset;

  Future<Map<String, PlanProgress>> _all() async {
    final raw = await _store.readSetting(_key);
    if (raw == null) return {};
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      return {
        for (final e in j.entries)
          if (e.value is Map && planById(e.key) != null)
            e.key: PlanProgress(
              planId: e.key,
              completed: ((e.value as Map)['done'] as List? ?? const []).whereType<int>().toSet(),
              readinessConfirmed: (e.value as Map)['ready'] == true,
            ),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(Map<String, PlanProgress> all) => _store.writeSetting(
        _key,
        jsonEncode({
          for (final p in all.values)
            p.planId: {'done': (p.completed.toList()..sort()), 'ready': p.readinessConfirmed},
        }),
      );

  Future<PlanProgress> progress(String planId) async =>
      (await _all())[planId] ?? PlanProgress(planId: planId, completed: const {}, readinessConfirmed: false);

  Future<Map<String, PlanProgress>> allProgress() => _all();

  /// Marks a session complete and records today as a session day for
  /// streaks ([at] defaults to now; resetting a plan keeps those days).
  Future<void> markDone(String planId, int sessionIndex, {DateTime? at}) async {
    final all = await _all();
    final cur = all[planId] ?? PlanProgress(planId: planId, completed: const {}, readinessConfirmed: false);
    all[planId] = PlanProgress(
      planId: planId,
      completed: {...cur.completed, sessionIndex},
      readinessConfirmed: cur.readinessConfirmed,
    );
    await _save(all);
    await ActivityLog(_store, utcOffset: _utcOffset).mark(at ?? DateTime.now(), ActivityKind.planSession, now: at);
  }

  Future<void> confirmReadiness(String planId) async {
    final all = await _all();
    final cur = all[planId] ?? PlanProgress(planId: planId, completed: const {}, readinessConfirmed: false);
    all[planId] = PlanProgress(planId: planId, completed: cur.completed, readinessConfirmed: true);
    await _save(all);
  }

  Future<void> reset(String planId) async {
    final all = await _all();
    all.remove(planId);
    await _save(all);
  }
}
