/// Sit-too-long nudges for desk days — pure Dart.
///
/// Evidence: Diaz et al. 2023 (Medicine & Science in Sports & Exercise,
/// randomized cross-over, n=11): during 8 h of sitting, 5 minutes of
/// light walking every 30 minutes cut post-meal blood-sugar spikes by
/// 58% vs sitting all day, and every walking schedule tested lowered
/// blood pressure by 4–5 mmHg. WHO: all adults should limit sedentary
/// time. Wording stays wellness-only.
///
/// v1 is TIME-BASED (no motion sensors, no extra permissions). Detecting
/// actual sitting needs Android's Activity Recognition (runtime
/// permission + Google Play services) and iOS Motion permission — a v2
/// upgrade so reminders can skip when you've just moved.
///
/// iOS keeps only a limited number of pending local notifications (64
/// is the commonly cited figure), shared with HUX's other reminders, so
/// sit nudges are capped at [maxScheduled]; long days use wider gaps.
library;

import 'nudge_planner.dart';

class SitNudgeSettings {
  final bool enabled;
  final TimeOfDayHm start;
  final TimeOfDayHm end;

  /// Minutes between reminders.
  final int intervalMinutes;

  /// DateTime.monday (1) … DateTime.sunday (7).
  final Set<int> days;

  static const intervals = [45, 60, 90];

  static const defaults = SitNudgeSettings(
    enabled: false,
    start: TimeOfDayHm(10, 0),
    end: TimeOfDayHm(18, 0),
    intervalMinutes: 60,
    days: {1, 2, 3, 4, 5},
  );

  const SitNudgeSettings({
    required this.enabled,
    required this.start,
    required this.end,
    required this.intervalMinutes,
    required this.days,
  });

  SitNudgeSettings copyWith({bool? enabled, TimeOfDayHm? start, TimeOfDayHm? end, int? intervalMinutes, Set<int>? days}) =>
      SitNudgeSettings(
        enabled: enabled ?? this.enabled,
        start: start ?? this.start,
        end: end ?? this.end,
        intervalMinutes: intervalMinutes ?? this.intervalMinutes,
        days: days ?? this.days,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'start': start.encode(),
        'end': end.encode(),
        'interval': intervalMinutes,
        'days': days.toList()..sort(),
      };

  factory SitNudgeSettings.fromJson(Map<String, Object?> j) {
    const d = defaults;
    final rawDays = j['days'];
    final days = rawDays is List ? rawDays.whereType<int>().where((x) => x >= 1 && x <= 7).toSet() : d.days;
    final interval = j['interval'];
    return SitNudgeSettings(
      enabled: j['enabled'] == true,
      start: TimeOfDayHm.decode(j['start'] as String?) ?? d.start,
      end: TimeOfDayHm.decode(j['end'] as String?) ?? d.end,
      intervalMinutes: interval is int && intervals.contains(interval) ? interval : d.intervalMinutes,
      days: days,
    );
  }
}

/// A nudge repeating weekly on [weekday] at [at].
class WeeklyNudge {
  final int id;
  final int weekday;
  final TimeOfDayHm at;
  final String title;
  final String body;
  const WeeklyNudge({required this.id, required this.weekday, required this.at, required this.title, required this.body});
}

class SitPlanner {
  /// Upper bound on sit reminders scheduled at once (see file header).
  static const maxScheduled = 45;

  /// First reminder comes one interval after the start time; skip slots
  /// this close to a walk-after-meal nudge (no double nudges).
  static const walkDedupeMinutes = 30;

  static const _idBase = 2000;

  static const _messages = [
    ('Time to stand up', 'You\'ve been sitting a while. Walk for 2–5 minutes — water bottle refill counts.'),
    ('Quick stretch break', 'Stand, roll your shoulders, walk to the window and back.'),
    ('Take the call standing?', 'Next call or message — do it on your feet.'),
    ('Chai break, walking style', 'A short walk now keeps your energy up for the afternoon.'),
  ];

  const SitPlanner();

  /// Slots of one day (local times), excluding ones near walk nudges.
  List<TimeOfDayHm> slots(SitNudgeSettings s, {WalkNudgeSettings? walk}) {
    if (s.end.minutesOfDay <= s.start.minutesOfDay) return const [];
    final walkTimes = walk == null ? const <TimeOfDayHm>[] : const NudgePlanner().dailyWalkNudges(walk).map((n) => n.at).toList();
    final result = <TimeOfDayHm>[];
    for (var m = s.start.minutesOfDay + s.intervalMinutes; m <= s.end.minutesOfDay; m += s.intervalMinutes) {
      final t = TimeOfDayHm(m ~/ 60, m % 60);
      final nearWalk = walkTimes.any((w) => (w.minutesOfDay - m).abs() <= walkDedupeMinutes);
      if (!nearWalk) result.add(t);
    }
    return result;
  }

  List<WeeklyNudge> weeklyNudges(SitNudgeSettings s, {WalkNudgeSettings? walk}) {
    if (!s.enabled || s.days.isEmpty) return const [];
    final daySlots = slots(s, walk: walk);
    final days = s.days.toList()..sort();
    final out = <WeeklyNudge>[];
    for (final day in days) {
      for (var i = 0; i < daySlots.length; i++) {
        if (out.length >= maxScheduled) return out;
        final (title, body) = _messages[i % _messages.length];
        out.add(WeeklyNudge(id: _idBase + day * 100 + i, weekday: day, at: daySlots[i], title: title, body: body));
      }
    }
    return out;
  }

  /// Would these settings exceed [maxScheduled]? (UI warns.)
  bool exceedsLimit(SitNudgeSettings s, {WalkNudgeSettings? walk}) =>
      slots(s, walk: walk).length * s.days.length > maxScheduled;
}
