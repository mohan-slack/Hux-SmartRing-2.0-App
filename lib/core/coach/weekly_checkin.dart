/// Weekly check-in: every Sunday evening the coach posts ONE message
/// about your week — the score, what went well, what to work on, and one
/// thing to try next week. Written ON THE PHONE from the Score and sleep
/// debt (no AI call, nothing sent), so it's free, private and exact.
///
/// Rules: once per week (Sunday 6 PM onward, or the next two days if the
/// app wasn't opened), only after the user agreed to the coach, and only
/// when there's enough data to say something true.
library;

import '../progress/goal_score.dart';
import '../storage/health_store.dart';
import 'coach_service.dart';

class WeeklyCheckIn {
  static const _key = 'weekly_checkin_v1';

  /// Sunday from this hour; Monday/Tuesday catch up.
  static const fromHour = 18;

  final HealthStore _store;
  final CoachService _coach;
  final Future<WeekScore> Function() _score;
  final Future<int?> Function()? _sleepDebtMin;
  final DateTime Function() _now;

  WeeklyCheckIn(this._store, this._coach,
      {required Future<WeekScore> Function() score, Future<int?> Function()? sleepDebtMin, DateTime Function()? now})
      : _score = score,
        _sleepDebtMin = sleepDebtMin,
        _now = now ?? DateTime.now;

  /// The Sunday this week's check-in belongs to, or null when none is due.
  static DateTime? dueSunday(DateTime local) {
    final d = DateTime(local.year, local.month, local.day);
    return switch (local.weekday) {
      DateTime.sunday => local.hour >= fromHour ? d : null,
      DateTime.monday => d.subtract(const Duration(days: 1)),
      DateTime.tuesday => d.subtract(const Duration(days: 2)),
      _ => null,
    };
  }

  static String _key4(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Posts the check-in if it's due and not yet posted. True if posted.
  Future<bool> postIfDue() async {
    final sunday = dueSunday(_now().toLocal());
    if (sunday == null) return false;
    if (await _store.readSetting(_key) == _key4(sunday)) return false;
    if (!await _coach.hasConsent()) return false;
    final text = compose(await _score(), sleepDebtMin: await _sleepDebtMin?.call());
    if (text == null) return false;
    await _coach.addLocalCoachMessage(text);
    await _store.writeSetting(_key, _key4(sunday));
    return true;
  }

  static const _tips = {
    ScorePart.sleep: 'Pick one bedtime and keep it 5 nights in a row — even 15 minutes earlier helps.',
    ScorePart.energy: 'Two easy days and one earlier night usually bring recovery back up.',
    ScorePart.move: 'A 10-minute walk after lunch on 4 days. Small, but it adds up.',
    ScorePart.food: 'Log one meal a day (breakfast is easiest) and add a protein to it — dal, curd, egg or paneer.',
  };

  /// The message, or null when there's too little data to be honest.
  static String? compose(WeekScore w, {int? sleepDebtMin}) {
    final overall = w.overall;
    final parts = [for (final p in w.parts.values) if (p.hasData) p]..sort((a, b) => b.score!.compareTo(a.score!));
    if (overall == null || parts.length < 2) return null;
    final best = parts.first, worst = parts.last;
    final change = w.change;
    final lines = <String>[
      'Your week with HUX: **$overall/100**'
          '${change == null ? '' : change == 0 ? ' — same as last week.' : change > 0 ? ' — up $change from last week.' : ' — down ${-change} from last week.'}',
      '- Went well: ${best.part.label} ${best.score} — ${_lower(best.facts.first)}',
      if (worst.part != best.part && worst.score! < 70)
        '- Work on: ${worst.part.label} ${worst.score} — ${_lower(worst.facts.first)}',
      if (sleepDebtMin != null && sleepDebtMin >= 60)
        '- Sleep debt: ${sleepDebtMin ~/ 60}h ${(sleepDebtMin % 60).toString().padLeft(2, '0')}m short over 7 nights.',
      '',
      'One thing for next week: ${_tips[worst.score! < 70 ? worst.part : (sleepDebtMin ?? 0) >= 120 ? ScorePart.sleep : worst.part]}',
      'Want me to make it a plan?',
    ];
    return lines.join('\n');
  }

  static String _lower(String s) => s.isEmpty ? s : '${s[0].toLowerCase()}${s.substring(1)}';
}
