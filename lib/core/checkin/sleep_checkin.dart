/// Morning check-in: "When did you sleep, and how rested do you feel?"
///
/// Why: most people have no watch or ring, so the health app has no
/// sleep for them and Charge stayed empty forever. Two taps each morning
/// give HUX a night to work with. For people WITH a wearable it adds the
/// one thing sensors can't measure: how rested they feel.
///
/// Kept ON THE PHONE, separate from synced sleep, so a check-in never
/// overwrites (or blocks) real data from a watch: when both exist for a
/// night, the synced night wins and only the "feel" is used.
library;

import 'dart:convert';

import '../ring/ring_models.dart';
import '../storage/health_store.dart';

/// 1 = exhausted … 5 = fully rested.
enum Rested { awful, poor, okay, good, great }

extension RestedLabel on Rested {
  int get score => index + 1;

  String get label => switch (this) {
        Rested.awful => 'Exhausted',
        Rested.poor => 'Tired',
        Rested.okay => 'Okay',
        Rested.good => 'Rested',
        Rested.great => 'Great',
      };
}

class SleepCheckIn {
  final DateTime bed;
  final DateTime wake;
  final Rested feel;

  /// True when the times came from a synced night (only [feel] is ours).
  final bool fromDevice;

  const SleepCheckIn({required this.bed, required this.wake, required this.feel, this.fromDevice = false});

  Duration get length => wake.difference(bed);

  /// As a night HUX can score: one "asleep" block, no stages.
  SleepSession toSession() => SleepSession(
        bedtime: bed,
        wakeTime: wake,
        segments: [SleepSegment(start: bed, end: wake, stage: SleepStage.light)],
      );

  Map<String, Object?> toJson() => {
        'bed': bed.toUtc().toIso8601String(),
        'wake': wake.toUtc().toIso8601String(),
        'feel': feel.name,
        if (fromDevice) 'dev': true,
      };

  static SleepCheckIn? fromJson(Object? j) {
    if (j is! Map) return null;
    final bed = DateTime.tryParse('${j['bed']}');
    final wake = DateTime.tryParse('${j['wake']}');
    final feel = Rested.values.where((r) => r.name == j['feel']).firstOrNull;
    if (bed == null || wake == null || feel == null || !wake.isAfter(bed)) return null;
    return SleepCheckIn(bed: bed, wake: wake, feel: feel, fromDevice: j['dev'] == true);
  }
}

class SleepCheckInService {
  static const _key = 'sleep_checkin_v1';
  static const keep = 90;

  /// Shortest / longest night we accept from a check-in.
  static const minNight = Duration(hours: 1);
  static const maxNight = Duration(hours: 16);

  /// The card shows between these local hours (morning, plus late
  /// risers and night-shift day sleepers until early afternoon).
  static const askFrom = 4, askUntil = 15;

  final HealthStore _store;
  final DateTime Function() _now;

  SleepCheckInService(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  Future<List<SleepCheckIn>> all() async {
    final raw = await _store.readSetting(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = (jsonDecode(raw) as List).map(SleepCheckIn.fromJson).whereType<SleepCheckIn>().toList()
        ..sort((a, b) => a.wake.compareTo(b.wake));
      return list;
    } catch (_) {
      return const [];
    }
  }

  static bool _sameLocalDay(DateTime a, DateTime b) {
    final x = a.toLocal(), y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  /// Saves (or replaces) the check-in for that wake-up day.
  Future<void> save(SleepCheckIn c) async {
    if (c.length < minNight || c.length > maxNight) {
      throw ArgumentError('A night must be between 1 and 16 hours.');
    }
    final list = [...await all()]..removeWhere((e) => _sameLocalDay(e.wake, c.wake));
    list.add(c);
    list.sort((a, b) => a.wake.compareTo(b.wake));
    final kept = list.length > keep ? list.sublist(list.length - keep) : list;
    await _store.writeSetting(_key, jsonEncode([for (final e in kept) e.toJson()]));
  }

  /// Today's check-in, if any.
  Future<SleepCheckIn?> today() async {
    final now = _now();
    return (await all()).where((c) => _sameLocalDay(c.wake, now)).lastOrNull;
  }

  /// How rested the user felt after the night that ended at [wake]
  /// (matched within 3 h, so a synced wake time a little off still pairs).
  Future<Rested?> feelFor(DateTime wake) async {
    for (final c in (await all()).reversed) {
      if (c.wake.difference(wake).abs() <= const Duration(hours: 3)) return c.feel;
    }
    return null;
  }

  static const _skipKey = 'sleep_checkin_skipped_on';

  static String _day(DateTime t) {
    final l = t.toLocal();
    return '${l.year}-${l.month}-${l.day}';
  }

  /// True in the morning window when today hasn't been checked in (or
  /// skipped) yet.
  Future<bool> shouldAsk() async {
    final now = _now();
    final h = now.toLocal().hour;
    if (h < askFrom || h >= askUntil) return false;
    if (await _store.readSetting(_skipKey) == _day(now)) return false;
    return await today() == null;
  }

  /// "Not now": don't ask again today.
  Future<void> skipToday() => _store.writeSetting(_skipKey, _day(_now()));

  /// Sleep sessions with bedtime in [from, to) — synced nights plus
  /// check-in nights the health app doesn't have. Use this instead of
  /// `store.sleepSessionsBetween` anywhere a "night" is shown or scored,
  /// so phone-only users see their check-ins everywhere.
  static Future<List<SleepSession>> nightsBetween(HealthStore store, DateTime from, DateTime to) async {
    final synced = await store.sleepSessionsBetween(from, to);
    List<SleepCheckIn> checkIns;
    try {
      checkIns = await SleepCheckInService(store).all();
    } catch (_) {
      return synced;
    }
    final f = from.toUtc(), t = to.toUtc();
    return merge(synced, [
      for (final c in checkIns)
        if (!c.bed.toUtc().isBefore(f) && c.bed.toUtc().isBefore(t)) c,
    ]);
  }

  /// [synced] plus check-in nights for nights the health app doesn't
  /// have. Synced nights always win.
  static List<SleepSession> merge(List<SleepSession> synced, List<SleepCheckIn> checkIns) {
    bool overlaps(SleepCheckIn c) =>
        synced.any((s) => s.bedtime.isBefore(c.wake) && s.wakeTime.isAfter(c.bed));
    final extra = [
      for (final c in checkIns)
        if (!c.fromDevice && !overlaps(c)) c.toSession(),
    ];
    if (extra.isEmpty) return synced;
    return [...synced, ...extra]..sort((a, b) => a.bedtime.compareTo(b.bedtime));
  }
}
