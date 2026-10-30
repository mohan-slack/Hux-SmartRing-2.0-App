/// Journey state on the phone: which program, the user's setup, how far
/// along, today's ticks, pause and rest passes. One active journey max.
///
/// Day logic (never "you failed"):
/// - The current day = days done (or skipped with a rest pass) + 1.
/// - Missed calendar days don't fail anything; the journey just waits.
///   After 2+ quiet days the UI says "Continue from day X".
/// - At most ONE journey day can be finished per calendar day.
library;

import 'dart:convert';

import '../nudges/nudge_planner.dart';
import '../profile/user_profile.dart';
import '../storage/health_store.dart';
import 'journey_content.dart';
import 'journey_models.dart';

class JourneySetup {
  final JourneyId id;
  final TimeOfDayHm wake;

  /// Sleep Reset only: when the user falls asleep now (we move from here).
  final TimeOfDayHm? usualBedtime;
  final Diet diet;
  final Budget budget;
  final FitnessLevel level;
  final bool remindWake;
  final bool remindMove;
  final bool remindWindDown;
  final TimeOfDayHm moveAt;

  const JourneySetup({
    required this.id,
    required this.wake,
    this.usualBedtime,
    this.diet = Diet.veg,
    this.budget = Budget.low,
    this.level = FitnessLevel.beginner,
    this.remindWake = true,
    this.remindMove = false,
    this.remindWindDown = true,
    this.moveAt = const TimeOfDayHm(18, 30),
  });

  Map<String, Object?> toJson() => {
        'id': id.name,
        'wake': wake.encode(),
        if (usualBedtime != null) 'usualBed': usualBedtime!.encode(),
        'diet': diet.name,
        'budget': budget.name,
        'level': level.name,
        'rWake': remindWake,
        'rMove': remindMove,
        'rWind': remindWindDown,
        'moveAt': moveAt.encode(),
      };

  static JourneySetup fromJson(Map<String, Object?> j) => JourneySetup(
        id: JourneyId.values.byName(j['id'] as String),
        wake: TimeOfDayHm.decode(j['wake'] as String?) ?? const TimeOfDayHm(6, 30),
        usualBedtime: TimeOfDayHm.decode(j['usualBed'] as String?),
        diet: Diet.values.where((d) => d.name == j['diet']).firstOrNull ?? Diet.veg,
        budget: Budget.values.where((b) => b.name == j['budget']).firstOrNull ?? Budget.low,
        level: FitnessLevel.values.where((l) => l.name == j['level']).firstOrNull ?? FitnessLevel.beginner,
        remindWake: j['rWake'] != false,
        remindMove: j['rMove'] == true,
        remindWindDown: j['rWind'] != false,
        moveAt: TimeOfDayHm.decode(j['moveAt'] as String?) ?? const TimeOfDayHm(18, 30),
      );
}

class JourneyState {
  final JourneySetup setup;
  final String startedOn; // yyyy-mm-dd (local)
  final int daysDone;
  final Set<DayItem> ticks; // for the CURRENT day
  final String? lastDoneOn; // local date a day was last finished/skipped
  final List<String> restPassDays; // local dates a rest pass was used
  final bool paused;
  final String? lastSeenOn;

  const JourneyState({
    required this.setup,
    required this.startedOn,
    this.daysDone = 0,
    this.ticks = const {},
    this.lastDoneOn,
    this.restPassDays = const [],
    this.paused = false,
    this.lastSeenOn,
  });

  JourneyDef get def => journeyDef(setup.id);
  int get currentDay => (daysDone + 1).clamp(1, def.days);
  bool get finished => daysDone >= def.days;

  JourneyState copyWith({
    JourneySetup? setup,
    int? daysDone,
    Set<DayItem>? ticks,
    String? lastDoneOn,
    List<String>? restPassDays,
    bool? paused,
    String? lastSeenOn,
  }) =>
      JourneyState(
        setup: setup ?? this.setup,
        startedOn: startedOn,
        daysDone: daysDone ?? this.daysDone,
        ticks: ticks ?? this.ticks,
        lastDoneOn: lastDoneOn ?? this.lastDoneOn,
        restPassDays: restPassDays ?? this.restPassDays,
        paused: paused ?? this.paused,
        lastSeenOn: lastSeenOn ?? this.lastSeenOn,
      );

  Map<String, Object?> toJson() => {
        'setup': setup.toJson(),
        'started': startedOn,
        'done': daysDone,
        'ticks': [for (final t in ticks) t.name],
        if (lastDoneOn != null) 'lastDone': lastDoneOn,
        'rest': restPassDays,
        'paused': paused,
        if (lastSeenOn != null) 'lastSeen': lastSeenOn,
      };

  static JourneyState fromJson(Map<String, Object?> j) => JourneyState(
        setup: JourneySetup.fromJson((j['setup'] as Map).cast<String, Object?>()),
        startedOn: j['started'] as String,
        daysDone: (j['done'] as num?)?.toInt() ?? 0,
        ticks: {
          for (final t in (j['ticks'] as List? ?? const []))
            ...DayItem.values.where((d) => d.name == t),
        },
        lastDoneOn: j['lastDone'] as String?,
        restPassDays: [for (final d in (j['rest'] as List? ?? const [])) d.toString()],
        paused: j['paused'] == true,
        lastSeenOn: j['lastSeen'] as String?,
      );
}

/// What Home shows: ONE line about today's journey day.
class JourneyHomeSummary {
  final String title;
  final int day;
  final int totalDays;
  final String line;
  final int ticksDone;
  final bool doneToday;
  final bool paused;

  const JourneyHomeSummary({
    required this.title,
    required this.day,
    required this.totalDays,
    required this.line,
    required this.ticksDone,
    required this.doneToday,
    required this.paused,
  });
}

class JourneyService {
  static const _key = 'journey_v1';
  static const _finishedKey = 'journeys_finished_v1';

  /// Bedtime moves at most this much at a time…
  static const shiftMinutes = 15;

  /// …every this many days.
  static const shiftEveryDays = 3;

  /// Sleep need used for the target (adult guide 7–9 h).
  static const sleepNeedMinutes = 7 * 60 + 30;
  static const windDownMinutes = 15;

  /// One rest pass per this many days.
  static const restPassEveryDays = 7;

  final HealthStore _store;
  final DateTime Function() _now;

  JourneyService(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime _parse(String k) {
    final p = k.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  String get _today => dayKey(_now());

  Future<JourneyState?> active() async {
    final raw = await _store.readSetting(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return JourneyState.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(JourneyState? s) =>
      _store.writeSetting(_key, s == null ? '' : jsonEncode(s.toJson()));

  /// Starts [setup] (replacing any active journey).
  Future<JourneyState> start(JourneySetup setup) async {
    final s = JourneyState(setup: setup, startedOn: _today, lastSeenOn: _today);
    await _save(s);
    return s;
  }

  Future<void> updateSetup(JourneySetup setup) async {
    final s = await active();
    if (s != null) await _save(s.copyWith(setup: setup));
  }

  Future<void> stop() => _save(null);

  Future<JourneyState?> setPaused(bool paused) async {
    final s = await active();
    if (s == null) return null;
    final next = s.copyWith(paused: paused);
    await _save(next);
    return next;
  }

  /// Ticks or unticks one item for today. When all 3 are ticked the day
  /// is finished — once per calendar day.
  Future<JourneyState?> toggle(DayItem item) async {
    final s = await active();
    if (s == null || s.finished || s.paused || doneToday(s)) return s;
    final ticks = {...s.ticks};
    if (!ticks.remove(item)) ticks.add(item);
    var next = s.copyWith(ticks: ticks, lastSeenOn: _today);
    if (ticks.length == DayItem.values.length) {
      next = JourneyState(
        setup: s.setup,
        startedOn: s.startedOn,
        daysDone: s.daysDone + 1,
        ticks: const {},
        lastDoneOn: _today,
        restPassDays: s.restPassDays,
        paused: s.paused,
        lastSeenOn: _today,
      );
      if (next.finished) await _recordFinished(next);
    }
    await _save(next);
    return next;
  }

  /// "Not today": uses the weekly rest pass and moves to the next day
  /// without breaking anything. False when no pass is left this week.
  Future<bool> skipToday() async {
    final s = await active();
    if (s == null || s.finished || doneToday(s) || !restPassAvailable(s)) return false;
    final next = JourneyState(
      setup: s.setup,
      startedOn: s.startedOn,
      daysDone: s.daysDone + 1,
      ticks: const {},
      lastDoneOn: _today,
      restPassDays: [...s.restPassDays, _today],
      paused: s.paused,
      lastSeenOn: _today,
    );
    if (next.finished) await _recordFinished(next);
    await _save(next);
    return true;
  }

  bool doneToday(JourneyState s) => s.lastDoneOn == _today;

  bool restPassAvailable(JourneyState s) {
    if (s.restPassDays.isEmpty) return true;
    final last = _parse(s.restPassDays.last);
    final today = _parse(_today);
    return today.difference(last).inDays >= restPassEveryDays;
  }

  /// Quiet calendar days since the journey was last used (for the
  /// gentle "Continue from day X" message).
  int quietDays(JourneyState s) {
    final last = s.lastDoneOn ?? s.startedOn;
    return _parse(_today).difference(_parse(last)).inDays - 1;
  }

  /// Tonight's "in bed by" time. Sleep Reset moves from the usual bedtime
  /// toward the target by [shiftMinutes] every [shiftEveryDays] days.
  TimeOfDayHm bedtimeFor(JourneyState s, {int? day}) {
    final d = day ?? s.currentDay;
    final target = s.setup.wake.plusMinutes(-(sleepNeedMinutes + windDownMinutes));
    final usual = s.setup.usualBedtime;
    if (s.setup.id != JourneyId.sleepReset21 || usual == null) return target;
    // Minutes the usual bedtime is LATER than the target (overnight-safe).
    final late = (usual.minutesOfDay - target.minutesOfDay + 24 * 60 + 12 * 60) % (24 * 60) - 12 * 60;
    if (late <= 0) return target; // already on time or earlier
    final moved = ((d - 1) ~/ shiftEveryDays) * shiftMinutes;
    return usual.plusMinutes(-(moved < late ? moved : late));
  }

  /// Today's plan for the active journey.
  JourneyDay today(JourneyState s) => journeyDay(s.setup.id, s.currentDay, s.setup.level);

  Map<MealSlot, List<MealOption>> mealsToday(JourneyState s) => mealsForDay(
        day: s.currentDay,
        diet: s.setup.diet,
        budget: s.setup.budget,
        lightDinner: s.setup.id == JourneyId.sleepReset21,
      );

  /// The reminders the user chose (max 3) — scheduled by NudgeService.
  List<DailyNudge> reminders(JourneyState s) {
    if (s.paused || s.finished) return const [];
    final bed = bedtimeFor(s);
    return [
      if (s.setup.remindWake)
        DailyNudge(
          id: NudgeIds.journeyWake,
          at: s.setup.wake,
          title: 'Good morning',
          body: 'Up at your journey time — get 10 minutes of daylight if you can.',
        ),
      if (s.setup.remindMove && s.setup.id == JourneyId.fitIn30)
        DailyNudge(
          id: NudgeIds.journeyMove,
          at: s.setup.moveAt,
          title: "Today's workout is ready",
          body: 'About ${today(s).workout.minutes} minutes. Warm-up first.',
        ),
      if (s.setup.remindWindDown)
        DailyNudge(
          id: NudgeIds.journeyWindDown,
          at: bed.plusMinutes(-30),
          title: 'Time to wind down',
          body: 'Lights low, phone away. In bed by ${bed.label}.',
        ),
    ];
  }

  Future<void> _recordFinished(JourneyState s) async {
    final raw = await _store.readSetting(_finishedKey);
    final list = <String>[];
    try {
      if (raw != null && raw.isNotEmpty) list.addAll((jsonDecode(raw) as List).map((e) => e.toString()));
    } catch (_) {}
    list.add('${s.setup.id.name}@$_today');
    await _store.writeSetting(_finishedKey, jsonEncode(list));
  }

  /// One line for Home, or null when no journey is active.
  Future<JourneyHomeSummary?> homeSummary() async {
    final s = await active();
    if (s == null) return null;
    final done = doneToday(s);
    final day = s.finished ? s.def.days : s.currentDay;
    final String line;
    if (s.finished) {
      line = 'Journey complete — see your summary.';
    } else if (s.paused) {
      line = 'Paused. Tap to continue when you\'re ready.';
    } else if (done) {
      line = 'Day done. See you tomorrow.';
    } else if (s.setup.id == JourneyId.sleepReset21) {
      line = 'Tonight: in bed by ${bedtimeFor(s).label}';
    } else {
      final w = today(s).workout;
      line = '${w.title} · ${w.minutes} min';
    }
    return JourneyHomeSummary(
      title: s.def.title,
      day: day,
      totalDays: s.def.days,
      line: line,
      ticksDone: s.ticks.length,
      doneToday: done || s.finished,
      paused: s.paused,
    );
  }
}
