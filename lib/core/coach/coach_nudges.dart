/// "Coach noticed": ONE pattern from the user's own history, shown on
/// Home as a question with a next step — e.g. "You log breakfast and
/// dinner, rarely lunch. Do you skip it?". Worked out ON THE PHONE from
/// data HUX already has; nothing is sent until the user opens the chat
/// and taps send.
///
/// Pure: give it meals, nights and steps, get back at most one nudge.
library;

import '../food/nutrients.dart';
import '../home/home_insights.dart';
import '../storage/health_store.dart';
import 'coach_service.dart';

enum CoachNudgeAction { askCoach, logMeal }

class CoachNudge {
  /// Stable id, used to hide it for a few days after "Not now".
  final String id;
  final CoachTopic topic;

  /// One short line: what HUX noticed.
  final String headline;

  /// The question or detail under it.
  final String detail;

  /// Placed in the coach's text box (the user still taps send).
  final String prompt;
  final CoachNudgeAction action;

  /// For [CoachNudgeAction.logMeal]: which meal to log.
  final MealType? meal;

  /// True for a "nice work" pattern (shown in a calmer colour).
  final bool positive;

  const CoachNudge({
    required this.id,
    required this.topic,
    required this.headline,
    required this.detail,
    required this.prompt,
    this.action = CoachNudgeAction.askCoach,
    this.meal,
    this.positive = false,
  });
}

class CoachNudges {
  CoachNudges._();

  static const _main = [MealType.breakfast, MealType.lunch, MealType.dinner];

  /// Picks the most useful pattern, or null when nothing stands out.
  ///
  /// [mealsByDay] is keyed by `DateTime.utc(y, m, d)` day labels and
  /// [today] is today's label. [nights7] / [sleep7] / [steps7] are oldest
  /// first; [steps7]'s last entry is today (still growing, so ignored).
  static CoachNudge? pick({
    required Map<DateTime, List<Meal>> mealsByDay,
    required DateTime today,
    List<NightWindow?> nights7 = const [],
    List<int?> sleep7 = const [],
    List<int?> steps7 = const [],
    double proteinGoalG = 0,
    Set<String> hidden = const {},
  }) {
    final week = [for (var i = 7; i >= 1; i--) mealsByDay[today.subtract(Duration(days: i))] ?? const <Meal>[]];
    final candidates = <CoachNudge?>[
      _shortNights(sleep7),
      _skippedMeal(week),
      _lateDinners(week),
      _bedtimeDrift(nights7),
      _lowProtein(week, proteinGoalG),
      _stepsDrop(steps7),
      _steadyBedtime(nights7),
    ];
    for (final c in candidates) {
      if (c != null && !hidden.contains(c.id)) return c;
    }
    return null;
  }

  // ---- sleep ----

  static CoachNudge? _shortNights(List<int?> sleep7) {
    if (sleep7.length < 3) return null;
    final last3 = sleep7.sublist(sleep7.length - 3);
    // 60 min floor: anything shorter is usually missing data, not a night.
    if (last3.any((m) => m == null || m < 60 || m >= 6 * 60)) return null;
    return const CoachNudge(
      id: 'short_nights',
      topic: CoachTopic.sleep,
      headline: '3 short nights in a row',
      detail: 'Each under 6 hours. A lighter day and an earlier night usually fix this faster than coffee.',
      prompt: "I've slept under 6 hours three nights in a row. What should I do today and tonight?",
    );
  }

  static int _after9pm(DateTime t) => ((t.hour * 60 + t.minute) - 21 * 60 + 24 * 60) % (24 * 60);

  static String _mins(int m) => m >= 60 ? '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m' : '$m min';

  static CoachNudge? _bedtimeDrift(List<NightWindow?> nights7) {
    final known = nights7.whereType<NightWindow>().toList();
    if (known.length < 5) return null;
    final beds = [for (final n in known) _after9pm(n.bed)];
    final recent = beds.sublist(beds.length - 3);
    final before = beds.sublist(0, beds.length - 3);
    double avg(List<int> v) => v.reduce((a, b) => a + b) / v.length;
    final drift = (avg(recent) - avg(before)).round();
    if (drift < 40) return null;
    final d = _mins((drift / 5).round() * 5);
    return CoachNudge(
      id: 'bedtime_drift',
      topic: CoachTopic.sleep,
      headline: 'Bedtime slid ~$d later',
      detail: 'Your last 3 nights started later than earlier in the week. Small, steady steps bring it back.',
      prompt: 'My bedtime has drifted about $d later this week. How do I bring it back without lying awake?',
    );
  }

  static CoachNudge? _steadyBedtime(List<NightWindow?> nights7) {
    final known = nights7.whereType<NightWindow>().toList();
    if (known.length < 5) return null;
    final beds = [for (final n in known) _after9pm(n.bed)]..sort();
    if (beds.last - beds.first > 40) return null;
    return CoachNudge(
      id: 'steady_bedtime',
      topic: CoachTopic.sleep,
      headline: 'Your bedtime is steady',
      detail: '${known.length} nights within 40 minutes of each other — the habit that helps sleep most.',
      prompt: 'My bedtime has been steady this week. What is the next thing I can improve for better sleep?',
      positive: true,
    );
  }

  // ---- food ----

  static CoachNudge? _skippedMeal(List<List<Meal>> week) {
    final logged = week.where((d) => d.isNotEmpty).length;
    if (logged < 4) return null;
    final count = {
      for (final t in _main) t: week.where((d) => d.any((m) => m.type == t)).length,
    };
    final usual = [for (final t in _main) if (count[t]! >= 3 && count[t]! >= logged * 0.6) t];
    final rare = [for (final t in _main) if (count[t]! <= 1) t]..sort((a, b) => count[a]!.compareTo(count[b]!));
    if (usual.isEmpty || rare.isEmpty) return null;
    final missing = rare.first;
    final m = missing.label.toLowerCase();
    final has = usual.map((t) => t.label.toLowerCase()).join(' and ');
    final n = count[missing]!;
    final cap = '${m[0].toUpperCase()}${m.substring(1)}';
    return CoachNudge(
      id: 'skip_${missing.name}',
      topic: CoachTopic.food,
      headline: 'You log $has, rarely $m',
      detail: n == 0
          ? 'No $m logged in the last week. Do you skip it, or just not log it?'
          : '$cap shows up only once this week. Do you skip it, or just not log it?',
      prompt: 'I usually skip $m or forget to log it. Does that matter for my energy, and what is an easy $m for me?',
      action: CoachNudgeAction.logMeal,
      meal: missing,
    );
  }

  static CoachNudge? _lateDinners(List<List<Meal>> week) {
    var late = 0;
    for (final day in week) {
      final hit = day.any((m) {
        if (m.type != MealType.dinner) return false;
        final h = m.loggedAt.toLocal().hour;
        return h >= 22 || h < 3;
      });
      if (hit) late++;
    }
    if (late < 3) return null;
    return CoachNudge(
      id: 'late_dinner',
      topic: CoachTopic.sleep,
      headline: 'Dinner is landing late',
      detail: '$late dinners after 10 PM this week. Late meals often make sleep lighter.',
      prompt: 'My dinner is often after 10 PM. How does that affect my sleep, and what can I change on busy days?',
    );
  }

  static CoachNudge? _lowProtein(List<List<Meal>> week, double goal) {
    if (goal <= 0) return null;
    final days = week.where((d) => d.isNotEmpty).toList();
    if (days.length < 3) return null;
    final avg = days.map((d) => d.fold<double>(0, (s, m) => s + m.total.proteinG)).reduce((a, b) => a + b) / days.length;
    if (avg >= goal * 0.6) return null;
    final a = avg.round(), g = goal.round();
    return CoachNudge(
      id: 'low_protein',
      topic: CoachTopic.food,
      headline: 'Protein is running low',
      detail: 'Your logged days average $a g of your $g g goal.',
      prompt: 'My protein averages about $a g a day against a $g g goal. Give me easy ways to add 20 g with my diet.',
    );
  }

  // ---- movement ----

  static CoachNudge? _stepsDrop(List<int?> steps7) {
    if (steps7.length < 7) return null;
    final before = steps7.sublist(0, 3), recent = steps7.sublist(3, 6); // today (index 6) is unfinished
    if (before.any((s) => s == null) || recent.any((s) => s == null)) return null;
    double avg(List<int?> v) => v.fold<int>(0, (a, b) => a + b!) / v.length;
    final b = avg(before), r = avg(recent);
    if (b < 3000 || r >= b * 0.6) return null;
    String k(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : '${v.round()}';
    return CoachNudge(
      id: 'steps_drop',
      topic: CoachTopic.move,
      headline: 'Your steps dipped',
      detail: 'About ${k(r)} a day lately, down from ${k(b)}. Busy week, or something else?',
      prompt: 'My steps dropped from about ${k(b)} to ${k(r)} a day this week. How do I get moving again without overdoing it?',
    );
  }
}

/// Remembers "Not now" so the same card doesn't come back for a few days.
class CoachNudgeStore {
  static const _key = 'coach_nudge_hidden_v1';
  static const hideDays = 3;

  final HealthStore _store;
  final DateTime Function() _now;

  CoachNudgeStore(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  Future<Map<String, DateTime>> _load() async {
    final raw = await _store.readSetting(_key);
    if (raw == null || raw.isEmpty) return {};
    final out = <String, DateTime>{};
    for (final part in raw.split(';')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      final at = DateTime.tryParse(part.substring(i + 1));
      if (at != null) out[part.substring(0, i)] = at;
    }
    return out;
  }

  /// Ids hidden in the last [hideDays] days.
  Future<Set<String>> hidden() async {
    final now = _now();
    return {
      for (final e in (await _load()).entries)
        if (now.difference(e.value).inDays < hideDays) e.key,
    };
  }

  Future<void> hide(String id) async {
    final now = _now();
    final all = await _load()
      ..removeWhere((_, at) => now.difference(at).inDays >= hideDays)
      ..[id] = now;
    await _store.writeSetting(_key, [for (final e in all.entries) '${e.key}=${e.value.toUtc().toIso8601String()}'].join(';'));
  }
}
