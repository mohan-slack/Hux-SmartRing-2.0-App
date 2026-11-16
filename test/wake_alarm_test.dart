/// Gentle wake alarm: settings, the three notifications, suggestions.
import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/nudges/notifier.dart';
import 'package:hux_app/core/nudges/nudge_planner.dart';
import 'package:hux_app/core/nudges/nudge_service.dart';
import 'package:hux_app/core/nudges/sit_planner.dart';
import 'package:hux_app/core/nudges/smart_notifier.dart';
import 'package:hux_app/core/nudges/wake_alarm.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Fake implements Notifier, WakeNotifier {
  bool grant = true;
  bool exact = true;
  final wake = <int, ({DailyNudge nudge, bool chime})>{};
  final daily = <int, DailyNudge>{};

  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async => grant;
  @override
  Future<void> scheduleDaily(DailyNudge nudge) async => daily[nudge.id] = nudge;
  @override
  Future<void> scheduleWeekly(WeeklyNudge nudge) async {}
  @override
  Future<void> scheduleOnce({required int id, required DateTime at, required String title, required String body}) async {}
  @override
  Future<bool> scheduleWake(DailyNudge nudge, {required bool chime}) async {
    wake[nudge.id] = (nudge: nudge, chime: chime);
    return exact;
  }

  @override
  Future<void> cancel(int id) async {
    wake.remove(id);
    daily.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    wake.clear();
    daily.clear();
  }
}

void main() {
  sqfliteFfiInit();
  Future<SqliteHealthStore> openStore() => SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);
  const on = WakeAlarmSettings(enabled: true, at: TimeOfDayHm(6, 30));

  group('settings', () {
    test('three notifications: quiet heads-up, chime, backup', () {
      final n = on.nudges();
      expect(n.map((e) => e.nudge.id), [NudgeIds.wakeSoon, NudgeIds.wakeNow, NudgeIds.wakeBackup]);
      expect(n.map((e) => e.nudge.at.label), ['6:20 AM', '6:30 AM', '6:35 AM']);
      expect(n.map((e) => e.chime), [false, true, true]);
    });

    test('off, or trimmed', () {
      expect(WakeAlarmSettings.defaults.nudges(), isEmpty);
      expect(on.copyWith(headsUp: false, backup: false).nudges().single.nudge.id, NudgeIds.wakeNow);
    });

    test('heads-up wraps past midnight', () {
      const s = WakeAlarmSettings(enabled: true, at: TimeOfDayHm(0, 5));
      expect(s.nudges().first.nudge.at.label, '11:55 PM');
    });

    test('round-trips', () {
      final back = WakeAlarmSettings.fromJson(on.copyWith(backup: false).toJson());
      expect(back.enabled, isTrue);
      expect(back.at.label, '6:30 AM');
      expect(back.headsUp, isTrue);
      expect(back.backup, isFalse);
    });
  });

  group('suggestions', () {
    test('goal first, then whole sleep cycles when different', () {
      final s = WakeTimes.suggest(DateTime(2026, 11, 16, 22, 30), goal: const Duration(hours: 8));
      expect(s.first.at.label, '6:45 AM'); // 22:30 + 15 min + 8 h
      expect(s.first.label, '6:45 AM · 8 h sleep');
      expect(s.last.at.label, '6:15 AM'); // 5 cycles = 7 h 30
      expect(s.last.label, contains('5 sleep cycles'));
    });

    test('one suggestion when the goal is already whole cycles', () {
      final s = WakeTimes.suggest(DateTime(2026, 11, 16, 23), goal: const Duration(hours: 7, minutes: 30));
      expect(s, hasLength(1));
      expect(s.single.at.label, '6:45 AM');
    });
  });

  group('service', () {
    test('saves, schedules through the wake channel, reports exactness', () async {
      final fake = _Fake();
      final service = NudgeService(await openStore(), fake);
      expect(await service.saveWakeSettings(on), WakeSaveResult.exact);
      expect(fake.wake.keys, NudgeIds.allWake);
      expect((await service.wakeSettings()).at.label, '6:30 AM');

      fake.exact = false;
      expect(await service.saveWakeSettings(on.copyWith(at: const TimeOfDayHm(7, 0))), WakeSaveResult.approximate);
      expect(fake.wake[NudgeIds.wakeNow]!.nudge.at.label, '7:00 AM');

      expect(await service.saveWakeSettings(on.copyWith(enabled: false)), WakeSaveResult.off);
      expect(fake.wake, isEmpty);
    });

    test('permission refused: stays off', () async {
      final fake = _Fake()..grant = false;
      final service = NudgeService(await openStore(), fake);
      expect(await service.saveWakeSettings(on), WakeSaveResult.refused);
      expect(fake.wake, isEmpty);
      expect((await service.wakeSettings()).enabled, isFalse);
    });

    test('quiet hours never silence the alarm; resync restores it', () async {
      final store = await openStore();
      final fake = _Fake();
      final smart = SmartNotifier(fake, store);
      await smart.setQuiet(const QuietWindow(22 * 60, 7 * 60));
      final service = NudgeService(store, smart);
      await service.saveWakeSettings(on);
      expect(fake.wake.keys, NudgeIds.allWake);

      fake.wake.clear();
      await NudgeService(store, smart).resync();
      expect(fake.wake.keys, NudgeIds.allWake);
    });
  });
}
