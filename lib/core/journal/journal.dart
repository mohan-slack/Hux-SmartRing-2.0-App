/// HUX Daily Journal
/// -----------------
/// One-tap tags for everyday Indian habits (chai, late dinner, sweets,
/// travel…), and — after a couple of weeks — what each one seems to do
/// to the user's OWN sleep and recovery.
///
/// Insights are honest comparisons, not claims: "on days you logged X
/// you slept 40 min less", only with enough days on both sides, and
/// always phrased as a pattern, never as cause or diagnosis.
library;

import 'dart:convert';

import '../ring/ring_models.dart';
import '../progress/activity_log.dart';
import '../storage/health_store.dart';
import '../trends/night_row.dart';

enum JournalTag {
  chai3plus,
  coffeeLate,
  lateDinner,
  heavyMeal,
  sweets,
  alcohol,
  screenInBed,
  workout,
  yoga,
  walkAfterMeal,
  dayNap,
  travel,
  stressfulDay,
  festival,
  unwell,
}

extension JournalTagLabel on JournalTag {
  String get label => switch (this) {
        JournalTag.chai3plus => 'Chai 3+ cups',
        JournalTag.coffeeLate => 'Coffee after 4 PM',
        JournalTag.lateDinner => 'Dinner after 10 PM',
        JournalTag.heavyMeal => 'Heavy or fried meal',
        JournalTag.sweets => 'Sweets',
        JournalTag.alcohol => 'Alcohol',
        JournalTag.screenInBed => 'Phone in bed',
        JournalTag.workout => 'Workout',
        JournalTag.yoga => 'Yoga or pranayama',
        JournalTag.walkAfterMeal => 'Walk after a meal',
        JournalTag.dayNap => 'Afternoon nap',
        JournalTag.travel => 'Travel',
        JournalTag.stressfulDay => 'Stressful day',
        JournalTag.festival => 'Festival or function',
        JournalTag.unwell => 'Feeling unwell',
      };

  /// Lower-case phrase for insight sentences ("days with sweets").
  String get phrase => switch (this) {
        JournalTag.chai3plus => '3+ cups of chai',
        JournalTag.coffeeLate => 'coffee after 4 PM',
        JournalTag.lateDinner => 'dinner after 10 PM',
        JournalTag.heavyMeal => 'a heavy or fried meal',
        JournalTag.sweets => 'sweets',
        JournalTag.alcohol => 'alcohol',
        JournalTag.screenInBed => 'phone in bed',
        JournalTag.workout => 'a workout',
        JournalTag.yoga => 'yoga or pranayama',
        JournalTag.walkAfterMeal => 'a walk after a meal',
        JournalTag.dayNap => 'an afternoon nap',
        JournalTag.travel => 'travel',
        JournalTag.stressfulDay => 'a stressful day',
        JournalTag.festival => 'a festival or function',
        JournalTag.unwell => 'feeling unwell',
      };
}

/// One pattern found in the user's own data.
class JournalInsight {
  final JournalTag tag;

  /// Average sleep difference on tagged nights vs other nights (minutes,
  /// negative = less sleep). Null when not enough sleep data.
  final int? sleepDiffMinutes;

  /// Average HRV difference as a fraction (-0.12 = 12% lower). Null when
  /// not enough HRV data.
  final double? hrvDiffPct;

  final int taggedNights;
  final int otherNights;

  /// The sentence shown to the user.
  final String text;

  const JournalInsight({
    required this.tag,
    required this.sleepDiffMinutes,
    required this.hrvDiffPct,
    required this.taggedNights,
    required this.otherNights,
    required this.text,
  });

  /// For sorting: how big the effect is, on a shared scale.
  double get strength =>
      ((sleepDiffMinutes ?? 0).abs() / 15.0) + ((hrvDiffPct ?? 0).abs() / 0.08);
}

class JournalInsights {
  /// Need at least this many nights WITH and WITHOUT a tag.
  static const minNightsEachSide = 3;

  /// Differences smaller than these are noise, not worth showing.
  static const minSleepDiffMinutes = 15;
  static const minHrvDiffPct = 0.08;

  static const maxInsights = 3;

  const JournalInsights._();

  /// [entries]: local day -> tags logged that day.
  /// [sessions]: sleep sessions; each is matched to the day whose
  /// evening it started on (same rule as Trends, see [nightKeyFor]).
  /// Only days that have ANY journal entry count as "other" days, so
  /// days the user never opened the journal don't skew the comparison.
  static List<JournalInsight> compute({
    required Map<DateTime, Set<JournalTag>> entries,
    required List<SleepSession> sessions,
    Duration? utcOffset,
  }) {
    final byNight = <DateTime, SleepSession>{};
    for (final s in sessions) {
      final key = nightKeyFor(s.bedtime, utcOffset: utcOffset);
      final existing = byNight[key];
      if (existing == null || s.totalSleep > existing.totalSleep) byNight[key] = s;
    }

    final loggedDays = entries.keys.where(byNight.containsKey).toList();
    final insights = <JournalInsight>[];

    for (final tag in JournalTag.values) {
      final withTag = loggedDays.where((d) => entries[d]!.contains(tag)).toList();
      final without = loggedDays.where((d) => !entries[d]!.contains(tag)).toList();
      if (withTag.length < minNightsEachSide || without.length < minNightsEachSide) continue;

      double? avgSleep(List<DateTime> days) {
        final v = [
          for (final d in days)
            if (byNight[d]!.segments.isNotEmpty) byNight[d]!.totalSleep.inMinutes.toDouble(),
        ];
        return v.length < minNightsEachSide ? null : v.reduce((a, b) => a + b) / v.length;
      }

      double? avgHrv(List<DateTime> days) {
        final v = [
          for (final d in days)
            if (byNight[d]!.avgHrvMs != null) byNight[d]!.avgHrvMs!.toDouble(),
        ];
        return v.length < minNightsEachSide ? null : v.reduce((a, b) => a + b) / v.length;
      }

      final sleepWith = avgSleep(withTag);
      final sleepWithout = avgSleep(without);
      final hrvWith = avgHrv(withTag);
      final hrvWithout = avgHrv(without);

      int? sleepDiff;
      if (sleepWith != null && sleepWithout != null) {
        final d = (sleepWith - sleepWithout).round();
        if (d.abs() >= minSleepDiffMinutes) sleepDiff = d;
      }
      double? hrvDiff;
      if (hrvWith != null && hrvWithout != null && hrvWithout > 0) {
        final d = (hrvWith - hrvWithout) / hrvWithout;
        if (d.abs() >= minHrvDiffPct) hrvDiff = d;
      }
      if (sleepDiff == null && hrvDiff == null) continue;

      insights.add(JournalInsight(
        tag: tag,
        sleepDiffMinutes: sleepDiff,
        hrvDiffPct: hrvDiff,
        taggedNights: withTag.length,
        otherNights: without.length,
        text: _sentence(tag, sleepDiff, hrvDiff, withTag.length),
      ));
    }

    insights.sort((a, b) => b.strength.compareTo(a.strength));
    return insights.take(maxInsights).toList();
  }

  static String _sentence(JournalTag tag, int? sleepDiff, double? hrvDiff, int nights) {
    final parts = <String>[];
    if (sleepDiff != null) {
      parts.add(sleepDiff < 0
          ? 'slept ${-sleepDiff} min less'
          : 'slept $sleepDiff min more');
    }
    if (hrvDiff != null) {
      final pct = (hrvDiff.abs() * 100).round();
      parts.add(hrvDiff < 0
          ? 'recovered $pct% less (HRV)'
          : 'recovered $pct% better (HRV)');
    }
    return 'On days with ${tag.phrase}, you ${parts.join(' and ')} '
        'than on other days ($nights nights).';
  }
}

/// Saves and loads journal entries; the only journal class screens use.
class JournalService {
  static const _key = 'journal_v1';

  /// Older entries are dropped on save (keeps the setting small).
  static const keepDays = 120;

  /// How far back insights look.
  static const insightWindow = Duration(days: 90);

  final HealthStore _store;
  final Duration? _utcOffset;

  /// [utcOffset] is for tests; null = the device's own timezone.
  JournalService(this._store, {Duration? utcOffset}) : _utcOffset = utcOffset;

  DateTime dayKey(DateTime t) => localDayKey(t, utcOffset: _utcOffset);

  Future<Map<DateTime, Set<JournalTag>>> loadAll() async {
    final raw = await _store.readSetting(_key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      final result = <DateTime, Set<JournalTag>>{};
      for (final e in decoded.entries) {
        final day = DateTime.tryParse(e.key);
        final list = e.value;
        if (day == null || list is! List) continue;
        final tags = {
          for (final t in JournalTag.values)
            if (list.contains(t.name)) t,
        };
        if (tags.isNotEmpty) result[DateTime.utc(day.year, day.month, day.day)] = tags;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<Set<JournalTag>> tagsFor(DateTime day) async =>
      (await loadAll())[dayKey(day)] ?? <JournalTag>{};

  Future<void> setTags(DateTime day, Set<JournalTag> tags, {DateTime? now}) async {
    final all = await loadAll();
    final key = dayKey(day);
    if (tags.isEmpty) {
      all.remove(key);
    } else {
      all[key] = tags;
    }
    final cutoff = dayKey(now ?? DateTime.now()).subtract(const Duration(days: keepDays));
    all.removeWhere((d, _) => d.isBefore(cutoff));
    final encoded = {
      for (final e in all.entries)
        _iso(e.key): [for (final t in e.value) t.name],
    };
    await _store.writeSetting(_key, jsonEncode(encoded));
    await ActivityLog(_store, utcOffset: _utcOffset)
        .markDay(key, ActivityKind.journal, done: tags.isNotEmpty, now: now);
  }

  /// How many days have at least one tag (for "keep logging" hints).
  Future<int> loggedDays() async => (await loadAll()).length;

  Future<List<JournalInsight>> insights({DateTime? now}) async {
    final at = (now ?? DateTime.now()).toUtc();
    final sessions = await _store.sleepSessionsBetween(at.subtract(insightWindow), at);
    return JournalInsights.compute(
      entries: await loadAll(),
      sessions: sessions,
      utcOffset: _utcOffset,
    );
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
