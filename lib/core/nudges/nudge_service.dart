/// Saves nudge settings and keeps the OS schedule in sync with them.
library;

import 'dart:convert';

import '../storage/health_store.dart';
import 'notifier.dart';
import 'nudge_planner.dart';
import 'sit_planner.dart';

class NudgeService {
  static const _walkKey = 'walk_nudge_v1';
  static const _sitKey = 'sit_nudge_v1';

  /// Ids of the sit nudges currently scheduled, so they can be cancelled
  /// exactly (their count changes with interval and days).
  static const _sitIdsKey = 'sit_nudge_ids';

  final HealthStore _store;
  final Notifier _notifier;
  final NudgePlanner _planner;

  final SitPlanner _sitPlanner;

  NudgeService(
    this._store,
    this._notifier, {
    NudgePlanner planner = const NudgePlanner(),
    SitPlanner sitPlanner = const SitPlanner(),
  })  : _planner = planner,
        _sitPlanner = sitPlanner;

  /// Removes every scheduled HUX reminder from the phone (walk, sit,
  /// air & heat). Used by "Delete my data" / "Delete account".
  Future<void> cancelAll() => _notifier.cancelAll();

  Future<WalkNudgeSettings> walkSettings() async {
    final raw = await _store.readSetting(_walkKey);
    if (raw == null) return WalkNudgeSettings.defaults;
    try {
      return WalkNudgeSettings.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return WalkNudgeSettings.defaults;
    }
  }

  /// Saves [s] and re-schedules. Turning ON asks the OS for permission;
  /// if refused, nudges stay OFF and this returns false.
  Future<bool> saveWalkSettings(WalkNudgeSettings s) async {
    var settings = s;
    if (settings.enabled) {
      final granted = await _notifier.requestPermission();
      if (!granted) settings = settings.copyWith(enabled: false);
    }
    await _store.writeSetting(_walkKey, jsonEncode(settings.toJson()));
    await _applyWalk(settings);
    // Sit slots skip times near walk nudges, so re-plan them too.
    await _applySit(await sitSettings(), settings);
    return settings.enabled == s.enabled;
  }

  Future<SitNudgeSettings> sitSettings() async {
    final raw = await _store.readSetting(_sitKey);
    if (raw == null) return SitNudgeSettings.defaults;
    try {
      return SitNudgeSettings.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return SitNudgeSettings.defaults;
    }
  }

  /// Same contract as [saveWalkSettings].
  Future<bool> saveSitSettings(SitNudgeSettings s) async {
    var settings = s;
    if (settings.enabled) {
      final granted = await _notifier.requestPermission();
      if (!granted) settings = settings.copyWith(enabled: false);
    }
    await _store.writeSetting(_sitKey, jsonEncode(settings.toJson()));
    await _applySit(settings, await walkSettings());
    return settings.enabled == s.enabled;
  }

  Future<void> _applySit(SitNudgeSettings s, WalkNudgeSettings walk) async {
    final raw = await _store.readSetting(_sitIdsKey);
    final old = raw == null ? const <int>[] : (jsonDecode(raw) as List).whereType<int>().toList();
    for (final id in old) {
      await _notifier.cancel(id);
    }
    final nudges = _sitPlanner.weeklyNudges(s, walk: walk);
    for (final n in nudges) {
      await _notifier.scheduleWeekly(n);
    }
    await _store.writeSetting(_sitIdsKey, jsonEncode([for (final n in nudges) n.id]));
  }

  /// Call on app start: the OS schedule can be lost (reinstall, data
  /// cleared), so rebuild it from saved settings.
  Future<void> resync() async {
    final walk = await walkSettings();
    await _applyWalk(walk);
    await _applySit(await sitSettings(), walk);
  }

  Future<void> _applyWalk(WalkNudgeSettings s) async {
    for (final id in NudgeIds.allWalk) {
      await _notifier.cancel(id);
    }
    for (final nudge in _planner.dailyWalkNudges(s)) {
      await _notifier.scheduleDaily(nudge);
    }
  }

  /// After a meal is logged: maybe a one-off walk nudge 10 minutes later.
  Future<void> onMealLogged(DateTime loggedAtLocal) async {
    final s = await walkSettings();
    final at = _planner.afterLoggedMeal(loggedAtLocal, s);
    if (at == null) return;
    await _notifier.scheduleOnce(
      id: NudgeIds.walkAfterLogged,
      at: at,
      title: 'Meal logged — walk it off?',
      body: 'A light 10-minute walk now is one of the easiest healthy habits.',
    );
  }
}
