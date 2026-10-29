/// Streaks that encourage, never punish.
///
/// Design notes (why it works this way):
/// - Habits take time: in Lally et al. (2010, Eur J Soc Psychol) habits
///   took a median of 66 days to feel automatic (range 18–254), and
///   missing ONE day did not set people back. So one missed day is
///   covered by a free "rest pass" (at most one per 7 days); only two
///   misses in a row end a streak.
/// - Broken streaks make people quit (Silverman & Barasch, 2023, J
///   Consumer Research). So today never counts as missed until it is
///   over, and after a break HUX says "welcome back", not "you lost".
/// - In a 61,000-person gym megastudy (Milkman et al., 2021, Nature),
///   rewarding a return after a missed workout was one of the best
///   nudges, and "fresh starts" (a new week or month, Dai, Milkman &
///   Riis, 2014) help people begin again.
/// - Weeks count as well as days: a "move week" is 3+ days with your
///   step goal or a guided session, so a busy day can't wipe out a
///   good week.
library;

/// What happened on one local day.
class DayRecord {
  /// `DateTime.utc(y, m, d)` day label.
  final DateTime day;
  final int? steps;
  final int? stepGoal;
  final bool planSession;
  final bool meal;
  final bool journal;

  const DayRecord({
    required this.day,
    this.steps,
    this.stepGoal,
    this.planSession = false,
    this.meal = false,
    this.journal = false,
  });

  bool get stepGoalMet => steps != null && stepGoal != null && steps! >= stepGoal!;

  /// Moved: step goal reached or a guided session done.
  bool get moved => stepGoalMet || planSession;

  /// Showed up: any healthy action (moved, logged a meal, or journaled).
  bool get active => moved || meal || journal;
}

class StreakSummary {
  /// Current daily streak, rest passes included.
  final int current;
  final int best;
  final int restPassesUsed;

  /// True when a missed day right now would be covered by a rest pass.
  final bool restPassReady;
  final bool todayDone;

  /// Weeks in a row with [StreakCalculator.moveDaysPerWeek]+ move days.
  final int moveWeeks;
  final int moveDaysThisWeek;
  final int? nextMilestone;

  /// One friendly line for the top of the screen.
  final String message;

  const StreakSummary({
    required this.current,
    required this.best,
    required this.restPassesUsed,
    required this.restPassReady,
    required this.todayDone,
    required this.moveWeeks,
    required this.moveDaysThisWeek,
    required this.nextMilestone,
    required this.message,
  });
}

class StreakCalculator {
  static const passGapDays = 7;
  static const moveDaysPerWeek = 3;
  static const milestones = [3, 7, 14, 21, 30, 50, 66, 100, 150, 200, 365];

  const StreakCalculator();

  /// [records]: any days (missing days = nothing happened). [today]: the
  /// `DateTime.utc(y, m, d)` label of the user's local today.
  StreakSummary calculate(Map<DateTime, DayRecord> records, DateTime today) {
    bool active(DateTime d) => records[d]?.active ?? false;
    final todayDone = active(today);

    // ---- current streak, walking back from today ----
    var d = todayDone ? today : _prev(today); // today isn't missed yet
    var current = 0;
    var passes = 0;
    DateTime? lastPass; // oldest pass so far (we walk backwards)
    DateTime? newestPass;
    final earliest = records.keys.isEmpty
        ? today
        : records.keys.reduce((a, b) => a.isBefore(b) ? a : b);
    while (!d.isBefore(earliest)) {
      if (active(d)) {
        current++;
      } else if (active(_prev(d)) &&
          (lastPass == null || lastPass.difference(d).inDays >= passGapDays) &&
          (current > 0 || d == _prev(today))) {
        current++;
        passes++;
        lastPass = d;
        newestPass ??= d;
      } else {
        break;
      }
      d = _prev(d);
    }

    // The most recent pass decides whether another is ready.
    final passReady = newestPass == null || today.difference(newestPass).inDays >= passGapDays;

    // ---- best streak ever, walking forward ----
    var best = current;
    var run = 0;
    DateTime? runPass;
    for (var x = earliest; x.isBefore(today); x = _next(x)) {
      if (active(x)) {
        run++;
      } else if (run > 0 &&
          active(_next(x)) &&
          (runPass == null || x.difference(runPass).inDays >= passGapDays)) {
        run++;
        runPass = x;
      } else {
        run = 0;
        runPass = null;
      }
      if (run > best) best = run;
    }

    // ---- move weeks (Mon–Sun) ----
    int moveDaysIn(DateTime monday) {
      var n = 0;
      for (var i = 0; i < 7; i++) {
        if (records[monday.add(Duration(days: i))]?.moved ?? false) n++;
      }
      return n;
    }

    final thisMonday = mondayOf(today);
    final thisWeek = moveDaysIn(thisMonday);
    var weeks = thisWeek >= moveDaysPerWeek ? 1 : 0; // in-progress week never breaks
    for (var m = thisMonday.subtract(const Duration(days: 7));
        !m.isBefore(mondayOf(earliest));
        m = m.subtract(const Duration(days: 7))) {
      if (moveDaysIn(m) < moveDaysPerWeek) break;
      weeks++;
    }

    final next = milestones.where((m) => m > current).firstOrNull;

    return StreakSummary(
      current: current,
      best: best,
      restPassesUsed: passes,
      restPassReady: passReady,
      todayDone: todayDone,
      moveWeeks: weeks,
      moveDaysThisWeek: thisWeek,
      nextMilestone: next,
      message: _message(
        current: current,
        best: best,
        todayDone: todayDone,
        passReady: passReady,
        today: today,
        hadHistory: records.values.any((r) => r.active),
      ),
    );
  }

  static String _message({
    required int current,
    required int best,
    required bool todayDone,
    required bool passReady,
    required DateTime today,
    required bool hadHistory,
  }) {
    final freshStart = today.weekday == DateTime.monday || today.day == 1;
    if (current == 0) {
      if (!hadHistory) return 'Do one healthy thing today — a walk, a meal log, or a journal tap — to start your streak.';
      final fresh = today.day == 1 ? 'New month' : (today.weekday == DateTime.monday ? 'New week' : null);
      return '${fresh != null ? '$fresh, fresh start. ' : ''}Welcome back — one small thing today starts a new streak'
          '${best >= 3 ? ' (your best is $best days)' : ''}.';
    }
    if (todayDone) {
      if (current == 66) return '66 days — about how long a habit takes to feel automatic. Brilliant.';
      if (current == best && current >= 3) return '$current days — your best streak yet!';
      return '$current-day streak. Today is done.';
    }
    if (!passReady) {
      return '$current-day streak. Your rest pass is used this week — one small thing today keeps it going.';
    }
    return '$current-day streak. ${freshStart ? 'Fresh start today — ' : ''}one small thing keeps it going '
        '(miss a day and a rest pass covers it).';
  }

  static DateTime mondayOf(DateTime day) => day.subtract(Duration(days: day.weekday - 1));
  static DateTime _prev(DateTime d) => DateTime.utc(d.year, d.month, d.day - 1);
  static DateTime _next(DateTime d) => DateTime.utc(d.year, d.month, d.day + 1);
}
