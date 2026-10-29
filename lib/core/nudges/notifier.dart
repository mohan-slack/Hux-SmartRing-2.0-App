/// The only thing in HUX that talks to the OS notification system —
/// behind an interface so the rest of the app (and tests) never touch
/// the plugin directly.
library;

import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'nudge_planner.dart';
import 'sit_planner.dart';

abstract class Notifier {
  Future<void> init();

  /// Asks the OS for permission (Android 13+, iOS). True when granted.
  Future<bool> requestPermission();

  Future<void> scheduleDaily(DailyNudge nudge);
  Future<void> scheduleWeekly(WeeklyNudge nudge);
  Future<void> scheduleOnce({required int id, required DateTime at, required String title, required String body});
  Future<void> cancel(int id);

  /// Removes every HUX reminder (used when data or the account is deleted).
  Future<void> cancelAll();
}

class LocalNotifier implements Notifier {
  static const _channelId = 'hux_nudges';
  static const _channelName = 'Gentle nudges';
  static const _channelDescription = 'Walk reminders and other small, helpful nudges';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      // White "H" silhouette (res/drawable-*/ic_stat_hux.png); Android
      // shows small icons as a single colour, tinted with [color].
      icon: 'ic_stat_hux',
      color: Color(0xFFF567B5), // HuxColors.accentPink
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Most HUX users are in India; a sane fallback beats UTC.
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        // Monochrome small icon; kept from resource shrinking by res/raw/keep.xml.
        android: AndroidInitializationSettings('@drawable/ic_stat_hux'),
        // Don't prompt at launch — we ask only when the user turns a nudge on.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.requestNotificationsPermission() ?? false;
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) return await ios.requestPermissions(alert: true, sound: true) ?? false;
    return false;
  }

  @override
  Future<void> scheduleDaily(DailyNudge nudge) async {
    await init();
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, nudge.at.hour, nudge.at.minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id: nudge.id,
      scheduledDate: next,
      notificationDetails: _details,
      // Inexact on purpose: a walk nudge doesn't need to-the-second timing,
      // and exact alarms need a special permission on Android 14+.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: nudge.title,
      body: nudge.body,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> scheduleWeekly(WeeklyNudge nudge) async {
    await init();
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, nudge.at.hour, nudge.at.minute);
    while (next.weekday != nudge.weekday || !next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id: nudge.id,
      scheduledDate: next,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: nudge.title,
      body: nudge.body,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  @override
  Future<void> scheduleOnce({required int id, required DateTime at, required String title, required String body}) async {
    await init();
    final when = tz.TZDateTime.from(at, tz.local);
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: when,
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: title,
      body: body,
    );
  }

  @override
  Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id: id);
  }

  @override
  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }
}
