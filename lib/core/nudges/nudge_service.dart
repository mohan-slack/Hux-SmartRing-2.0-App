/// Saves nudge settings and keeps the OS schedule in sync with them.
library;

import 'dart:convert';

import '../meaning/evening_timing.dart';
import '../storage/health_store.dart';
import 'notifier.dart';
import 'nudge_planner.dart';
import 'sit_planner.dart';
import 'smart_notifier.dart';

class NudgeService {
  static const _walkKey = 'walk_nudge_v1';
  static const _sitKey = 'sit_nudge_v1';

  /// Ids of the sit nudges currently scheduled, so they can be cancelled
  /// exactly (their count changes with interval and days).
  static const _sitIdsKey = 'sit_nudge_ids';
  static const _briefingKey = 'morning_briefing_v1';
  static const _briefingStreakKey = 'morning_briefing_streak';

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

  /// Cancels every HUX notification (all reminders and alerts). Used
  /// when the phone's data is wiped for a different account.
  Future<void> cancelEverything() => _notifier.cancelAll();

  // ---- morning briefing ------------------------------------------------

  Future<BriefingSettings> briefingSettings() async {
    final raw = await _store.readSetting(_briefingKey);
    if (raw == null) return BriefingSettings.defaults;
    try {
      return BriefingSettings.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return BriefingSettings.defaults;
    }
  }

  /// Same contract as [saveWalkSettings]: false = permission refused.
  Future<bool> saveBriefingSettings(BriefingSettings s) async {
    var settings = s;
    if (settings.enabled) {
      final granted = await _notifier.requestPermission();
      if (!granted) settings = settings.copyWith(enabled: false);
    }
    await _store.writeSetting(_briefingKey, jsonEncode(settings.toJson()));
    await _applyBriefing(settings);
    return settings.enabled == s.enabled;
  }

  /// Re-words tomorrow's briefing with the latest streak (call when the
  /// app opens). Local notifications can't compute at fire time, so the
  /// text says what's waiting, not a number that may be stale.
  Future<void> refreshBriefing({int? streakDays}) async {
    if (streakDays != null) await _store.writeSetting(_briefingStreakKey, '$streakDays');
    await _applyBriefing(await briefingSettings());
  }

  Future<void> _applyBriefing(BriefingSettings s) async {
    await _notifier.cancel(NudgeIds.morningBriefing);
    if (!s.enabled) return;
    final streak = int.tryParse(await _store.readSetting(_briefingStreakKey) ?? '');
    await _notifier.scheduleDaily(DailyNudge(
      id: NudgeIds.morningBriefing,
      at: s.at,
      title: streak != null && streak >= 2 ? 'Good morning — keep your $streak-day streak going' : 'Good morning',
      body: "Your charge, today's plan and step goal are ready. Takes 10 seconds.",
    ));
  }

  // ---- journeys ---------------------------------------------------------

  /// Replaces the journey reminders with [nudges] (max 3). Turning any on
  /// asks for notification permission; returns false if refused.
  Future<bool> setJourneyReminders(List<DailyNudge> nudges) async {
    for (final id in NudgeIds.allJourney) {
      await _notifier.cancel(id);
    }
    if (nudges.isEmpty) return true;
    if (!await _notifier.requestPermission()) return false;
    for (final n in nudges.take(3)) {
      await _notifier.scheduleDaily(n);
    }
    return true;
  }

  // ---- cycle -------------------------------------------------------------

  /// The ONE discreet cycle reminder at [at] (null = none). Wording never
  /// mentions periods: lock screens are seen by others. False = refused.
  Future<bool> setCycleHeadsUp(DateTime? at) async {
    await _notifier.cancel(NudgeIds.cycleHeadsUp);
    if (at == null) return true;
    if (!await _notifier.requestPermission()) return false;
    await _notifier.scheduleOnce(
      id: NudgeIds.cycleHeadsUp,
      at: at,
      title: 'Heads-up from HUX',
      body: 'A gentle check-in for the next few days. Open HUX when you have a moment.',
    );
    return true;
  }

  // ---- evening timing (last chai, dinner) --------------------------------

  static const _eveningKey = 'evening_timing_on';

  Future<bool> eveningRemindersOn() async => (await _store.readSetting(_eveningKey)) == 'yes';

  /// Turns the two evening reminders on/off. Asks permission when turning
  /// on; false = refused. [bed] schedules tonight's right away.
  Future<bool> setEveningReminders(bool on, {DateTime? bed}) async {
    if (on && !await _notifier.requestPermission()) return false;
    await _store.writeSetting(_eveningKey, on ? 'yes' : 'no');
    await refreshEvening(bed);
    return true;
  }

  /// Re-plans tonight's two reminders from today's bedtime (it moves day
  /// to day). Call whenever the readout reloads.
  Future<void> refreshEvening(DateTime? bed, {DateTime? now}) async {
    await _notifier.cancel(NudgeIds.lastCaffeine);
    await _notifier.cancel(NudgeIds.dinnerBy);
    if (bed == null || !await eveningRemindersOn()) return;
    final t = EveningTiming.forBed(bed.toLocal());
    final at = (now ?? DateTime.now()).toLocal();
    String clock(DateTime d) {
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
    }

    final chai = t.lastCaffeine.subtract(const Duration(minutes: 30));
    if (chai.isAfter(at)) {
      await _notifier.scheduleOnce(
        id: NudgeIds.lastCaffeine,
        at: chai,
        title: 'Last chai or coffee soon',
        body: 'Have it by ${clock(t.lastCaffeine)} — later caffeine keeps sleep light tonight.',
      );
    }
    final dinner = t.lastMeal.subtract(const Duration(minutes: 30));
    if (dinner.isAfter(at)) {
      await _notifier.scheduleOnce(
        id: NudgeIds.dinnerBy,
        at: dinner,
        title: 'Dinner by ${clock(t.lastMeal)}',
        body: 'Eating 2–3 hours before bed (${clock(t.bed)}) helps deeper sleep.',
      );
    }
  }

  /// Next Sunday 7 PM: "your week is ready" (the coach's weekly check-in).
  /// Never asks for permission itself — it only shows if reminders are
  /// already allowed. [on] false cancels it.
  Future<void> setWeeklyCheckIn(bool on, {DateTime? now}) async {
    await _notifier.cancel(NudgeIds.weeklyCheckIn);
    if (!on) return;
    final t = (now ?? DateTime.now()).toLocal();
    var at = DateTime(t.year, t.month, t.day, 19);
    while (at.weekday != DateTime.sunday || !at.isAfter(t)) {
      at = at.add(const Duration(days: 1));
    }
    await _notifier.scheduleOnce(
      id: NudgeIds.weeklyCheckIn,
      at: at,
      title: 'Your week with HUX',
      body: 'Your coach looked at your week — and has one thing to try next.',
    );
  }

  // ---- smarter reminders ---------------------------------------------------

  /// Quiet hours follow your sleep: [bed] tonight's target, [wake] the
  /// matching wake time. Re-plans repeating reminders only when the window
  /// moved by 30+ min (no churn every reload).
  Future<void> learnQuiet({required DateTime bed, required DateTime wake}) async {
    final n = _notifier;
    if (n is! SmartNotifier) return;
    final b = bed.toLocal(), w = wake.toLocal();
    final next = QuietWindow.fromSleep(bedMinute: b.hour * 60 + b.minute, wakeMinute: w.hour * 60 + w.minute);
    final old = await n.quiet();
    int gap(int x, int y) {
      final d = (x - y).abs() % 1440;
      return d > 720 ? 1440 - d : d;
    }

    if (gap(old.start, next.start) < 30 && gap(old.end, next.end) < 30) return;
    await n.setQuiet(next);
    await resync();
  }

  /// Rule 2 (see smart_notifier.dart): pauses walk reminders that were
  /// ignored on 6 of the last 7 days. Returns true when it paused them.
  Future<bool> backOffIgnored({DateTime? now}) async {
    final walk = await walkSettings();
    if (!walk.enabled) return false;
    final e = NudgeEngagement(_store, now: now == null ? null : () => now);
    final opens = await e.opens();
    final at = now ?? DateTime.now();
    final lunch = NudgeEngagement.ignored(opens, walk.lunch, at);
    final dinner = NudgeEngagement.ignored(opens, walk.dinner, at);
    if (lunch == null || dinner == null) return false;
    if (lunch < NudgeEngagement.ignoredDays || dinner < NudgeEngagement.ignoredDays) return false;
    final off = walk.copyWith(enabled: false);
    await _store.writeSetting(_walkKey, jsonEncode(off.toJson()));
    await _applyWalk(off);
    await e.setAutoPaused({...await e.autoPaused(), 'walk'});
    return true;
  }

  /// "Turn back on" after an auto-pause.
  Future<bool> resumeWalk() async {
    final e = NudgeEngagement(_store);
    await e.setAutoPaused({...await e.autoPaused()}..remove('walk'));
    return saveWalkSettings((await walkSettings()).copyWith(enabled: true));
  }

  /// Call on app start: the OS schedule can be lost (reinstall, data
  /// cleared), so rebuild it from saved settings.
  Future<void> resync() async {
    final walk = await walkSettings();
    await _applyWalk(walk);
    await _applySit(await sitSettings(), walk);
    await _applyBriefing(await briefingSettings());
  }

  Future<void> _applyWalk(WalkNudgeSettings s) async {
    // Not walkAfterLogged: that one-off was set by a meal just logged and
    // must survive a cold start (resync runs on every launch).
    for (final id in NudgeIds.allWalk.where((id) => id != NudgeIds.walkAfterLogged)) {
      await _notifier.cancel(id);
    }
    if (!s.enabled) await _notifier.cancel(NudgeIds.walkAfterLogged);
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
