/// Quiet hours from sleep; pausing reminders nobody uses.
/// Run with: flutter test test/smart_notifier_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/nudges/notifier.dart';
import 'package:hux_app/core/nudges/nudge_planner.dart';
import 'package:hux_app/core/nudges/sit_planner.dart';
import 'package:hux_app/core/nudges/smart_notifier.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeNotifier implements Notifier {
  final daily = <int>[];
  final once = <int, DateTime>{};
  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> scheduleDaily(DailyNudge n) async => daily.add(n.id);
  @override
  Future<void> scheduleWeekly(WeeklyNudge n) async {}
  @override
  Future<void> scheduleOnce({required int id, required DateTime at, required String title, required String body}) async =>
      once[id] = at;
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> cancelAll() async {}
}

void main() {
  sqfliteFfiInit();

  test('quiet window across midnight', () {
    final w = QuietWindow.fromSleep(bedMinute: 23 * 60, wakeMinute: 7 * 60); // 22:30–07:00
    expect(w.contains(22 * 60 + 45), isTrue);
    expect(w.contains(3 * 60), isTrue);
    expect(w.contains(7 * 60), isFalse); // wake is fine
    expect(w.contains(13 * 60), isFalse);
    // Night shift: sleeps 9:00–16:00.
    final n = QuietWindow.fromSleep(bedMinute: 9 * 60, wakeMinute: 16 * 60);
    expect(n.contains(12 * 60), isTrue);
    expect(n.contains(22 * 60), isFalse);
  });

  test('repeating reminders in sleep are skipped; one-offs move to after waking', () async {
    final store = await SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);
    final inner = FakeNotifier();
    final n = SmartNotifier(inner, store);
    await n.setQuiet(QuietWindow.fromSleep(bedMinute: 23 * 60, wakeMinute: 7 * 60));
    await n.scheduleDaily(const DailyNudge(id: 1, at: TimeOfDayHm(23, 15), title: 't', body: 'b'));
    await n.scheduleDaily(const DailyNudge(id: 2, at: TimeOfDayHm(13, 0), title: 't', body: 'b'));
    await n.scheduleDaily(const DailyNudge(id: NudgeIds.morningBriefing, at: TimeOfDayHm(6, 30), title: 't', body: 'b'));
    expect(inner.daily, [2, NudgeIds.morningBriefing]); // 11:15 PM skipped; user-chosen briefing kept

    await n.scheduleOnce(id: 9, at: DateTime(2026, 11, 4, 5, 0), title: 't', body: 'b');
    expect(inner.once[9], DateTime(2026, 11, 4, 7, 15)); // after waking
    await n.scheduleOnce(id: 10, at: DateTime(2026, 11, 3, 23, 10), title: 't', body: 'b');
    expect(inner.once[10], DateTime(2026, 11, 4, 7, 15)); // still under 12 h → moved
    await store.close();
  });

  test('ignored = no app open within 3 h after the reminder', () {
    final now = DateTime(2026, 11, 10, 9);
    const lunch = TimeOfDayHm(13, 0);
    // Opens every morning only, for 9 days → lunch ignored on all 7 days.
    final mornings = [for (var d = 1; d <= 9; d++) DateTime(2026, 11, d, 8)];
    expect(NudgeEngagement.ignored(mornings, lunch, now), 7);
    // Plus an open at 2 PM on 3 days → ignored 4.
    final some = [...mornings, for (final d in [7, 8, 9]) DateTime(2026, 11, d, 14)]..sort();
    expect(NudgeEngagement.ignored(some, lunch, now), 4);
    // Less than a week of history: don't judge.
    expect(NudgeEngagement.ignored([DateTime(2026, 11, 8, 8)], lunch, now), isNull);
  });
}
