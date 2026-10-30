/// HUX Nudge Planner — WHEN and WHAT to remind, as pure Dart.
///
/// Walk after meals: a short, light walk soon after eating. A 2022
/// meta-analysis (Buffey et al., Sports Medicine) found that breaking up
/// sitting with light walking lowered after-meal glucose and insulin vs
/// sitting, and walking beat standing. Wording stays wellness-only.
///
/// Rules:
/// - fixed daily nudges [walkDelay] after the user's usual lunch/dinner;
/// - an optional one-off nudge after a meal is LOGGED, unless a fixed
///   nudge is already close by (no double nudging);
/// - never during quiet hours.
library;

class TimeOfDayHm {
  final int hour;
  final int minute;
  const TimeOfDayHm(this.hour, this.minute);

  int get minutesOfDay => hour * 60 + minute;

  TimeOfDayHm plusMinutes(int m) {
    final total = (minutesOfDay + m) % (24 * 60);
    return TimeOfDayHm(total ~/ 60, total % 60);
  }

  /// "1:45 PM".
  String get label {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h:${minute.toString().padLeft(2, '0')} ${hour < 12 ? 'AM' : 'PM'}';
  }

  String encode() => '$hour:$minute';

  static TimeOfDayHm? decode(String? s) {
    final parts = s?.split(':');
    if (parts == null || parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDayHm(h, m);
  }

  @override
  bool operator ==(Object other) => other is TimeOfDayHm && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => minutesOfDay;
}

class WalkNudgeSettings {
  final bool enabled;
  final TimeOfDayHm lunch;
  final TimeOfDayHm dinner;
  final bool afterLoggedMeal;

  /// No nudges from [quietStart] to [quietEnd] (wraps midnight).
  final TimeOfDayHm quietStart;
  final TimeOfDayHm quietEnd;

  static const defaults = WalkNudgeSettings(
    enabled: false,
    lunch: TimeOfDayHm(13, 30),
    dinner: TimeOfDayHm(20, 30),
    afterLoggedMeal: true,
    quietStart: TimeOfDayHm(22, 30),
    quietEnd: TimeOfDayHm(7, 0),
  );

  const WalkNudgeSettings({
    required this.enabled,
    required this.lunch,
    required this.dinner,
    required this.afterLoggedMeal,
    required this.quietStart,
    required this.quietEnd,
  });

  WalkNudgeSettings copyWith({bool? enabled, TimeOfDayHm? lunch, TimeOfDayHm? dinner, bool? afterLoggedMeal}) =>
      WalkNudgeSettings(
        enabled: enabled ?? this.enabled,
        lunch: lunch ?? this.lunch,
        dinner: dinner ?? this.dinner,
        afterLoggedMeal: afterLoggedMeal ?? this.afterLoggedMeal,
        quietStart: quietStart,
        quietEnd: quietEnd,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'lunch': lunch.encode(),
        'dinner': dinner.encode(),
        'afterLoggedMeal': afterLoggedMeal,
        'quietStart': quietStart.encode(),
        'quietEnd': quietEnd.encode(),
      };

  factory WalkNudgeSettings.fromJson(Map<String, Object?> j) {
    const d = defaults;
    return WalkNudgeSettings(
      enabled: j['enabled'] == true,
      lunch: TimeOfDayHm.decode(j['lunch'] as String?) ?? d.lunch,
      dinner: TimeOfDayHm.decode(j['dinner'] as String?) ?? d.dinner,
      afterLoggedMeal: j['afterLoggedMeal'] != false,
      quietStart: TimeOfDayHm.decode(j['quietStart'] as String?) ?? d.quietStart,
      quietEnd: TimeOfDayHm.decode(j['quietEnd'] as String?) ?? d.quietEnd,
    );
  }
}

/// A daily repeating nudge at a local time.
class DailyNudge {
  final int id;
  final TimeOfDayHm at;
  final String title;
  final String body;
  const DailyNudge({required this.id, required this.at, required this.title, required this.body});
}

/// Opt-in daily morning briefing ("today's charge and plan are ready").
class BriefingSettings {
  final bool enabled;
  final TimeOfDayHm at;

  const BriefingSettings({required this.enabled, required this.at});

  static const defaults = BriefingSettings(enabled: false, at: TimeOfDayHm(7, 30));

  BriefingSettings copyWith({bool? enabled, TimeOfDayHm? at}) =>
      BriefingSettings(enabled: enabled ?? this.enabled, at: at ?? this.at);

  Map<String, Object?> toJson() => {'enabled': enabled, 'at': at.encode()};

  static BriefingSettings fromJson(Map<String, Object?> j) => BriefingSettings(
        enabled: j['enabled'] == true,
        at: TimeOfDayHm.decode(j['at'] as String?) ?? defaults.at,
      );
}

class NudgeIds {
  const NudgeIds._();
  static const morningBriefing = 1201;
  static const journeyWake = 1301;
  static const journeyMove = 1302;
  static const journeyWindDown = 1303;
  static const allJourney = [journeyWake, journeyMove, journeyWindDown];

  /// Cycle: one discreet heads-up (never says "period").
  static const cycleHeadsUp = 1401;
  static const walkLunch = 1001;
  static const walkDinner = 1002;
  static const walkAfterLogged = 1003;
  static const allWalk = [walkLunch, walkDinner, walkAfterLogged];
}

class NudgePlanner {
  /// Nudge this long after the meal starts/ends — soon, but not mid-meal.
  static const walkDelay = 20;

  /// After a LOGGED meal, nudge this many minutes later.
  static const afterLogDelay = 10;

  /// Skip the after-log nudge if a fixed nudge is within this window.
  static const dedupeWindow = 45;

  const NudgePlanner();

  static bool inQuietHours(TimeOfDayHm t, WalkNudgeSettings s) {
    final m = t.minutesOfDay;
    final start = s.quietStart.minutesOfDay;
    final end = s.quietEnd.minutesOfDay;
    return start <= end ? (m >= start && m < end) : (m >= start || m < end);
  }

  List<DailyNudge> dailyWalkNudges(WalkNudgeSettings s) {
    if (!s.enabled) return const [];
    final result = <DailyNudge>[];
    final lunchAt = s.lunch.plusMinutes(walkDelay);
    if (!inQuietHours(lunchAt, s)) {
      result.add(DailyNudge(
        id: NudgeIds.walkLunch,
        at: lunchAt,
        title: 'Lunch done? Time for a short walk',
        body: '10 easy minutes now helps your body handle the meal. Even a walk around the office counts.',
      ));
    }
    final dinnerAt = s.dinner.plusMinutes(walkDelay);
    if (!inQuietHours(dinnerAt, s)) {
      result.add(DailyNudge(
        id: NudgeIds.walkDinner,
        at: dinnerAt,
        title: 'Chalo, a 10-minute walk?',
        body: 'A gentle stroll after dinner — terrace, corridor or colony road.',
      ));
    }
    return result;
  }

  /// When to nudge after a meal logged at [loggedAt] (local wall time),
  /// or null when switched off, in quiet hours, or a fixed nudge is near.
  DateTime? afterLoggedMeal(DateTime loggedAt, WalkNudgeSettings s) {
    if (!s.enabled || !s.afterLoggedMeal) return null;
    final when = loggedAt.add(const Duration(minutes: afterLogDelay));
    final t = TimeOfDayHm(when.hour, when.minute);
    if (inQuietHours(t, s)) return null;
    for (final fixed in dailyWalkNudges(s)) {
      final diff = (fixed.at.minutesOfDay - t.minutesOfDay).abs();
      final wrapped = diff > 720 ? 1440 - diff : diff;
      if (wrapped <= dedupeWindow) return null;
    }
    return when;
  }
}
