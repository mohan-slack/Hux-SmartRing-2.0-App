/// The coach's Sunday check-in: when it's due, what it says, once a week.
/// Run with: flutter test test/weekly_checkin_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/coach/coach_context.dart';
import 'package:hux_app/core/coach/coach_service.dart';
import 'package:hux_app/core/coach/weekly_checkin.dart';
import 'package:hux_app/core/progress/goal_score.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

WeekScore week({int? sleep, int? move, int? food, int? lastWeek}) => WeekScore({
      ScorePart.sleep: PartScore(ScorePart.sleep, sleep, const [], const ['Average 7h 20m a night (6 nights)']),
      ScorePart.energy: const PartScore(ScorePart.energy, null, [], ['Needs 3 nights of ring data.']),
      ScorePart.move: PartScore(ScorePart.move, move, const [], const ['Step goal reached on 2 of 7 days']),
      ScorePart.food: PartScore(ScorePart.food, food, const [], const ['Food logged on 3 of 7 days']),
    }, lastWeek: lastWeek);

void main() {
  sqfliteFfiInit();

  test('due on Sunday from 6 PM, caught up Mon/Tue, never mid-week', () {
    expect(WeeklyCheckIn.dueSunday(DateTime(2026, 11, 8, 17)), isNull); // Sun 5 PM
    expect(WeeklyCheckIn.dueSunday(DateTime(2026, 11, 8, 19)), DateTime(2026, 11, 8));
    expect(WeeklyCheckIn.dueSunday(DateTime(2026, 11, 9, 8)), DateTime(2026, 11, 8)); // Mon
    expect(WeeklyCheckIn.dueSunday(DateTime(2026, 11, 10, 8)), DateTime(2026, 11, 8)); // Tue
    expect(WeeklyCheckIn.dueSunday(DateTime(2026, 11, 11, 8)), isNull); // Wed
  });

  test('says the score, what went well, what to work on, one thing to try', () {
    final text = WeeklyCheckIn.compose(week(sleep: 82, move: 40, food: 55, lastWeek: 52), sleepDebtMin: 150)!;
    expect(text, contains('**59/100**'));
    expect(text, contains('up 7 from last week'));
    expect(text, contains('Went well: Sleep 82'));
    expect(text, contains('Work on: Move 40'));
    expect(text, contains('Sleep debt: 2h 30m'));
    expect(text, contains('10-minute walk after lunch'));
  });

  test('too little data -> no message', () {
    expect(WeeklyCheckIn.compose(week(sleep: 80)), isNull); // one part only
  });

  test('posts once per week, only with coach consent', () async {
    final store = await SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);
    var now = DateTime(2026, 11, 8, 19);
    final coach = CoachService(store, loadContext: () async => const CoachContext(partOfDay: 'evening'), now: () => now);
    final w = WeeklyCheckIn(store, coach, score: () async => week(sleep: 80, move: 60), now: () => now);
    expect(await w.postIfDue(), isFalse); // no consent yet
    await coach.giveConsent();
    expect(await w.postIfDue(), isTrue);
    expect(await w.postIfDue(), isFalse); // already this week
    now = DateTime(2026, 11, 9, 9); // Monday, same week
    expect(await w.postIfDue(), isFalse);
    expect((await coach.history()).single.role, ChatRole.coach);
    now = DateTime(2026, 11, 15, 20); // next Sunday
    expect(await w.postIfDue(), isTrue);
    await store.close();
  });
}
