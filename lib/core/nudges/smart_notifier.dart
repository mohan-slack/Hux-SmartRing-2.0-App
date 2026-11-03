/// Smarter reminders, in two small rules:
///
/// 1. SLEEP QUIET HOURS. Nothing buzzes between 30 min before your usual
///    bedtime and your usual wake time (learned from your nights, so it
///    fits night-shift sleepers too). A one-off reminder that would land
///    inside is moved to just after you wake; a repeating one is skipped.
/// 2. BACK OFF WHEN IGNORED. If a walk reminder fired on 6 of the last 7
///    days and you never opened HUX within 3 hours after, HUX pauses it
///    and says so on Home (one tap turns it back on). Reminders you don't
///    use are noise.
library;

import 'dart:convert';

import '../storage/health_store.dart';
import 'notifier.dart';
import 'nudge_planner.dart';
import 'sit_planner.dart';

/// Minutes after midnight; [start] may be > [end] (crosses midnight).
class QuietWindow {
  final int start;
  final int end;
  const QuietWindow(this.start, this.end);

  /// Used until HUX has learned your nights.
  static const fallback = QuietWindow(22 * 60 + 30, 6 * 60 + 30);

  bool contains(int minuteOfDay) =>
      start <= end ? minuteOfDay >= start && minuteOfDay < end : minuteOfDay >= start || minuteOfDay < end;

  /// From usual bed/wake (minutes after midnight): bed − 30 min to wake.
  factory QuietWindow.fromSleep({required int bedMinute, required int wakeMinute}) =>
      QuietWindow((bedMinute - 30 + 1440) % 1440, wakeMinute % 1440);

  Map<String, Object?> toJson() => {'s': start, 'e': end};
  static QuietWindow? fromJson(Object? j) =>
      j is Map && j['s'] is int && j['e'] is int ? QuietWindow(j['s'] as int, j['e'] as int) : null;
}

/// Wraps the real [Notifier] and applies rule 1.
class SmartNotifier implements Notifier {
  static const _quietKey = 'sleep_quiet_v1';

  final Notifier _inner;
  final HealthStore _store;

  SmartNotifier(this._inner, this._store);

  Future<QuietWindow> quiet() async {
    try {
      final raw = await _store.readSetting(_quietKey);
      return QuietWindow.fromJson(raw == null ? null : jsonDecode(raw)) ?? QuietWindow.fallback;
    } catch (_) {
      return QuietWindow.fallback;
    }
  }

  /// Learned from the plan: call when the usual bed/wake is known.
  Future<void> setQuiet(QuietWindow w) => _store.writeSetting(_quietKey, jsonEncode(w.toJson()));

  @override
  Future<void> init() => _inner.init();

  @override
  Future<bool> requestPermission() => _inner.requestPermission();

  /// Times the user picked themselves (an alarm-like briefing, the
  /// journey wake-up) are never silenced.
  static const _userTimed = {NudgeIds.morningBriefing, NudgeIds.journeyWake};

  @override
  Future<void> scheduleDaily(DailyNudge nudge) async {
    if (!_userTimed.contains(nudge.id) && (await quiet()).contains(nudge.at.hour * 60 + nudge.at.minute)) return;
    await _inner.scheduleDaily(nudge);
  }

  @override
  Future<void> scheduleWeekly(WeeklyNudge nudge) async {
    if ((await quiet()).contains(nudge.at.hour * 60 + nudge.at.minute)) return;
    await _inner.scheduleWeekly(nudge);
  }

  @override
  Future<void> scheduleOnce({required int id, required DateTime at, required String title, required String body}) async {
    final w = await quiet();
    var when = at;
    final local = at.toLocal();
    if (w.contains(local.hour * 60 + local.minute)) {
      // Just after waking (same reminder, delivered when you can use it).
      var moved = DateTime(local.year, local.month, local.day, w.end ~/ 60, w.end % 60).add(const Duration(minutes: 15));
      if (!moved.isAfter(local)) moved = moved.add(const Duration(days: 1));
      // A reminder that only makes sense tonight (chai, dinner) is dropped
      // rather than delivered tomorrow morning.
      if (moved.difference(local) > const Duration(hours: 12)) return;
      when = moved;
    }
    await _inner.scheduleOnce(id: id, at: when, title: title, body: body);
  }

  @override
  Future<void> cancel(int id) => _inner.cancel(id);

  @override
  Future<void> cancelAll() => _inner.cancelAll();
}

/// Rule 2: app opens vs reminder times.
class NudgeEngagement {
  static const _opensKey = 'app_opens_v1';
  static const _pausedKey = 'nudges_auto_paused_v1';
  static const keepDays = 14;

  /// "Opened soon after" = within this long after the reminder.
  static const window = Duration(hours: 3);

  /// Ignored on at least this many of the last [lookback] days → pause.
  static const ignoredDays = 6, lookback = 7;

  final HealthStore _store;
  final DateTime Function() _now;

  NudgeEngagement(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  Future<List<DateTime>> opens() async {
    final raw = await _store.readSetting(_opensKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [for (final s in jsonDecode(raw) as List) if (DateTime.tryParse('$s') case final DateTime d) d];
    } catch (_) {
      return const [];
    }
  }

  /// Call when the app comes to the foreground.
  Future<void> recordOpen() async {
    final now = _now();
    final kept = [...await opens()]..removeWhere((d) => now.difference(d) > const Duration(days: keepDays));
    // One entry per 10 minutes is plenty.
    if (kept.isNotEmpty && now.difference(kept.last) < const Duration(minutes: 10)) return;
    kept.add(now);
    await _store.writeSetting(_opensKey, jsonEncode([for (final d in kept) d.toUtc().toIso8601String()]));
  }

  /// Days (of the last [lookback]) on which a reminder at [at] was
  /// followed by NO app open within [window]. Null = too little history.
  static int? ignored(List<DateTime> opens, TimeOfDayHm at, DateTime now) {
    if (opens.isEmpty || now.difference(opens.first.toLocal()).inDays < lookback) return null;
    var n = 0;
    for (var d = 1; d <= lookback; d++) {
      final day = now.toLocal().subtract(Duration(days: d));
      final fire = DateTime(day.year, day.month, day.day, at.hour, at.minute);
      final hit = opens.any((o) {
        final l = o.toLocal();
        return !l.isBefore(fire) && l.isBefore(fire.add(window));
      });
      if (!hit) n++;
    }
    return n;
  }

  /// Kinds HUX paused on its own (shown on Home until dismissed).
  Future<Set<String>> autoPaused() async {
    final raw = await _store.readSetting(_pausedKey);
    if (raw == null || raw.isEmpty) return const {};
    return raw.split(',').where((s) => s.isNotEmpty).toSet();
  }

  Future<void> setAutoPaused(Set<String> kinds) => _store.writeSetting(_pausedKey, kinds.join(','));
}
