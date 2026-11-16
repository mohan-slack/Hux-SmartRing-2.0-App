/// Gentle wake alarm: a quiet heads-up 10 minutes before, a soft rising
/// chime at your wake time, and one backup 5 minutes later.
///
/// It is delivered as a notification, so a phone on silent or Do Not
/// Disturb can mute it — the UI says so, and to keep the phone's own
/// alarm for must-wake mornings.
///
/// Pure settings + suggestions; scheduling lives in NudgeService.
library;

import 'nudge_planner.dart';

class WakeAlarmSettings {
  final bool enabled;
  final TimeOfDayHm at;

  /// Quiet heads-up 10 minutes before (no sound).
  final bool headsUp;

  /// One more chime 5 minutes after.
  final bool backup;

  const WakeAlarmSettings({required this.enabled, required this.at, this.headsUp = true, this.backup = true});

  static const defaults = WakeAlarmSettings(enabled: false, at: TimeOfDayHm(6, 30));

  static const headsUpMinutes = 10;
  static const backupMinutes = 5;

  WakeAlarmSettings copyWith({bool? enabled, TimeOfDayHm? at, bool? headsUp, bool? backup}) => WakeAlarmSettings(
        enabled: enabled ?? this.enabled,
        at: at ?? this.at,
        headsUp: headsUp ?? this.headsUp,
        backup: backup ?? this.backup,
      );

  Map<String, Object?> toJson() => {'enabled': enabled, 'at': at.encode(), 'headsUp': headsUp, 'backup': backup};

  static WakeAlarmSettings fromJson(Map<String, Object?> j) => WakeAlarmSettings(
        enabled: j['enabled'] == true,
        at: TimeOfDayHm.decode(j['at'] as String?) ?? defaults.at,
        headsUp: j['headsUp'] != false,
        backup: j['backup'] != false,
      );

  /// The notifications this alarm needs, in time order.
  List<({DailyNudge nudge, bool chime})> nudges() {
    if (!enabled) return const [];
    return [
      if (headsUp)
        (
          nudge: DailyNudge(
            id: NudgeIds.wakeSoon,
            at: at.plusMinutes(-headsUpMinutes),
            title: 'Waking in $headsUpMinutes minutes',
            body: 'Nothing to do yet. Let some light in if you can.',
          ),
          chime: false,
        ),
      (
        nudge: DailyNudge(
          id: NudgeIds.wakeNow,
          at: at,
          title: 'Good morning — ${at.label}',
          body: 'Same wake time every day is the anchor. Open HUX to see how you slept.',
        ),
        chime: true,
      ),
      if (backup)
        (
          nudge: DailyNudge(
            id: NudgeIds.wakeBackup,
            at: at.plusMinutes(backupMinutes),
            title: 'Time to get up',
            body: 'Feet on the floor, then daylight for 10 minutes.',
          ),
          chime: true,
        ),
    ];
  }
}

/// What happened when the alarm was saved.
enum WakeSaveResult {
  /// On, and the phone allows on-the-minute timing.
  exact,

  /// On, but the phone may deliver it a few minutes late.
  approximate,

  /// Notifications not allowed — alarm stays off.
  refused,

  /// Turned off.
  off,
}

/// A wake time worth suggesting for tonight's bedtime.
class WakeSuggestion {
  final TimeOfDayHm at;
  final Duration sleep;
  final String label;

  const WakeSuggestion({required this.at, required this.sleep, required this.label});
}

class WakeTimes {
  WakeTimes._();

  /// Minutes most people take to fall asleep.
  static const fallAsleepMinutes = 15;

  /// One sleep cycle (about 90 minutes).
  static const cycleMinutes = 90;

  static String _hm(Duration d) => d.inMinutes % 60 == 0 ? '${d.inHours} h' : '${d.inHours} h ${d.inMinutes % 60} min';

  /// For [bed] (in bed by) and the sleep [goal]: the goal itself, and
  /// the nearest whole number of sleep cycles when that differs — waking
  /// at the end of a cycle usually feels lighter.
  static List<WakeSuggestion> suggest(DateTime bed, {required Duration goal}) {
    final asleep = bed.toLocal().add(const Duration(minutes: fallAsleepMinutes));
    TimeOfDayHm at(Duration sleep) {
      final t = asleep.add(sleep);
      return TimeOfDayHm(t.hour, t.minute);
    }

    final cycles = (goal.inMinutes / cycleMinutes).round().clamp(4, 6);
    final byCycle = Duration(minutes: cycles * cycleMinutes);
    return [
      WakeSuggestion(at: at(goal), sleep: goal, label: '${at(goal).label} · ${_hm(goal)} sleep'),
      if ((byCycle - goal).inMinutes.abs() >= 15)
        WakeSuggestion(at: at(byCycle), sleep: byCycle, label: '${at(byCycle).label} · $cycles sleep cycles'),
    ];
  }
}
