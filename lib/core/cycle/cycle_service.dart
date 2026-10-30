/// Cycle: saves logs and settings locally and answers "where am I?".
///
/// Everything is ONE local setting (`cycle_v1`). Nothing here talks to
/// the network; the Health import reads from the phone's own health app.
library;

import 'dart:convert';

import '../nudges/nudge_service.dart';
import '../storage/health_store.dart';
import 'cycle_content.dart';
import 'cycle_health_source.dart';
import 'cycle_models.dart';
import 'cycle_predictor.dart';

/// The ONE line Home shows (null when Cycle is off or hidden).
class CycleHomeSummary {
  final int? day;
  final int cycleDays;
  final String title;
  final String line;
  final bool locked;
  final bool showLogButton;

  const CycleHomeSummary({
    this.day,
    required this.cycleDays,
    required this.title,
    required this.line,
    this.locked = false,
    this.showLogButton = false,
  });
}

class CycleService {
  static const _key = 'cycle_v1';

  final HealthStore _store;
  final DateTime Function() _now;
  final CyclePeriodSource? _source;

  CycleService(this._store, {DateTime Function()? now, CyclePeriodSource? source})
      : _now = now ?? DateTime.now,
        _source = source;

  DateTime get today => dayOf(_now());

  Future<CycleData> load() async {
    final raw = await _store.readSetting(_key);
    if (raw == null || raw.isEmpty) return CycleData.empty;
    try {
      return CycleData.fromJson(jsonDecode(raw));
    } catch (_) {
      return CycleData.empty;
    }
  }

  Future<CycleData> _save(CycleData d) async {
    await _store.writeSetting(_key, jsonEncode(d.toJson()));
    return d;
  }

  /// Turns Cycle on. [lastStart] = the most recent period start, if known.
  Future<CycleData> enable(CycleSettings settings, {DateTime? lastStart}) async {
    var d = (await load()).copyWith(settings: settings.copyWith(enabled: true));
    d = await _save(d);
    if (lastStart != null) d = await logStart(lastStart);
    return d;
  }

  Future<CycleData> updateSettings(CycleSettings s) async => _save((await load()).copyWith(settings: s));

  /// Wipes every period, log and setting (Cycle goes back to off).
  Future<void> deleteAll() => _store.writeSetting(_key, '');

  // ---- logging ---------------------------------------------------------

  /// "Period started" on [day] (today by default).
  Future<CycleData> logStart([DateTime? day]) async {
    final d = await load();
    final start = dayOf(day ?? _now());
    if (start.isAfter(today)) return d;
    final periods = [...d.periods];

    // Already inside a logged period → nothing to do.
    for (final p in periods) {
      final end = p.end ?? addDays(p.start, CyclePredictor.autoCloseDays - 1);
      if (!start.isBefore(p.start) && !start.isAfter(end)) return d;
    }
    // A start within 3 days of an existing one is a correction: move it.
    final near = periods.indexWhere((p) => daysBetween(start, p.start).abs() <= 3);
    if (near >= 0) {
      final p = periods[near];
      periods[near] = PeriodRecord(start: start, end: p.end != null && p.end!.isBefore(start) ? null : p.end, source: 'manual');
    } else {
      // Close an earlier open period at its usual length.
      for (var i = 0; i < periods.length; i++) {
        final p = periods[i];
        if (p.end == null && p.start.isBefore(start)) {
          final usualEnd = addDays(p.start, d.settings.usualPeriodDays - 1);
          periods[i] = p.copyWith(end: usualEnd.isBefore(start) ? usualEnd : addDays(start, -1));
        }
      }
      periods.add(PeriodRecord(start: start));
    }
    final days = {...d.days};
    final k = dayKey(start);
    final log = days[k] ?? const DayLog();
    if (log.flow == null) days[k] = DayLog(flow: FlowLevel.medium, symptoms: log.symptoms);
    return _save(d.copyWith(periods: periods, days: days));
  }

  /// "Period ended" on [day]: closes the latest period that started
  /// before it (up to 14 days long). Returns null if there is none.
  Future<CycleData?> logEnd([DateTime? day]) async {
    final d = await load();
    final end = dayOf(day ?? _now());
    final periods = [...d.periods];
    for (var i = periods.length - 1; i >= 0; i--) {
      final p = periods[i];
      if (p.start.isAfter(end)) continue;
      if (daysBetween(p.start, end) > 13) return null;
      periods[i] = p.copyWith(end: end);
      return _save(d.copyWith(periods: periods));
    }
    return null;
  }

  Future<CycleData> removePeriod(DateTime start) async {
    final d = await load();
    return _save(d.copyWith(periods: d.periods.where((p) => p.start != dayOf(start)).toList()));
  }

  Future<CycleData> setDay(DateTime day, DayLog log) async {
    final d = await load();
    final days = {...d.days};
    final k = dayKey(dayOf(day));
    if (log.isEmpty) {
      days.remove(k);
    } else {
      days[k] = log;
    }
    return _save(d.copyWith(days: days));
  }

  // ---- Health import ---------------------------------------------------

  /// Reads the last year of period days from Apple Health / Health
  /// Connect and adds periods HUX doesn't have yet. Returns how many.
  Future<int> importFromHealth() async {
    final source = _source;
    if (source == null) return 0;
    final now = _now();
    final bleeding = await source.bleedingDays(now.subtract(const Duration(days: 365)), now);
    final runs = groupIntoPeriods(bleeding);
    final d = await load();
    final periods = [...d.periods];
    var added = 0;
    for (final r in runs) {
      final clash = periods.any((p) {
        final pEnd = p.end ?? addDays(p.start, CyclePredictor.autoCloseDays - 1);
        final overlaps = !r.start.isAfter(pEnd) && !r.end!.isBefore(p.start);
        return overlaps || daysBetween(r.start, p.start).abs() <= 3;
      });
      if (clash) continue;
      periods.add(r);
      added++;
    }
    if (added > 0) await _save(d.copyWith(periods: periods));
    return added;
  }

  /// Consecutive bleeding days (gaps ≤ 2 days) → one period, max 14 days.
  static List<PeriodRecord> groupIntoPeriods(List<DateTime> days) {
    final sorted = {for (final d in days) dayOf(d)}.toList()..sort();
    final out = <PeriodRecord>[];
    DateTime? start, end;
    for (final d in sorted) {
      if (start != null && daysBetween(end!, d) <= 2 && daysBetween(start, d) < 14) {
        end = d;
        continue;
      }
      if (start != null) out.add(PeriodRecord(start: start, end: end, source: 'health'));
      start = d;
      end = d;
    }
    if (start != null) out.add(PeriodRecord(start: start, end: end, source: 'health'));
    return out;
  }

  // ---- reading ---------------------------------------------------------

  CycleForecast forecastFor(CycleData d) => CyclePredictor.forecast(d, _now());

  /// Null when Cycle is off.
  Future<CycleForecast?> forecast() async {
    final d = await load();
    return d.settings.enabled ? forecastFor(d) : null;
  }

  /// For phase-matched baselines. Null when off or in a mode without
  /// phases (hormonal, pregnant).
  Future<CyclePhaseResolver?> resolver() async {
    final d = await load();
    if (!d.settings.enabled || !d.settings.mode.hasPhases || d.periods.isEmpty) return null;
    return CyclePhaseResolver(d);
  }

  /// First 3 days of a period with "gentle moves" on.
  Future<bool> gentleToday() async {
    final d = await load();
    if (!d.settings.enabled || !d.settings.gentleMoves) return false;
    final f = forecastFor(d);
    return f.phase == CyclePhase.period && (f.dayOfCycle ?? 99) <= 3;
  }

  Future<bool> periodToday() async {
    final d = await load();
    return d.settings.enabled && forecastFor(d).phase == CyclePhase.period;
  }

  /// The ONE word the coach may get — only with the user's OK.
  Future<String?> coachPhase() async {
    final d = await load();
    if (!d.settings.enabled || !d.settings.useInCoach) return null;
    return forecastFor(d).phase?.label;
  }

  Future<CycleHomeSummary?> homeSummary() async {
    final d = await load();
    final s = d.settings;
    if (!s.enabled || !s.showOnHome) return null;
    final f = forecastFor(d);
    if (s.lock) {
      return CycleHomeSummary(cycleDays: f.avgCycleDays, title: 'Cycle', line: 'Locked · tap to open', locked: true);
    }
    return CycleHomeSummary(
      day: f.dayOfCycle,
      cycleDays: f.avgCycleDays,
      title: f.dayOfCycle == null
          ? 'Cycle'
          : 'Day ${f.dayOfCycle}${f.phase != null ? ' · ${f.phase!.label}' : ''}',
      line: CycleContent.statusLine(f),
      showLogButton: f.nearWindow,
    );
  }

  // ---- reminder --------------------------------------------------------

  /// 9 AM, 2 days before the likely range opens (null = none to set).
  DateTime? headsUpAt(CycleData d) {
    if (!d.settings.enabled || !d.settings.headsUp || !d.settings.mode.predicts) return null;
    final f = forecastFor(d);
    if (f.from == null || f.periodOpen || f.isLate) return null;
    final day = addDays(f.from!, -2);
    final at = DateTime(day.year, day.month, day.day, 9);
    return at.isAfter(_now()) ? at : null;
  }

  /// Keeps the one discreet reminder in line with the latest data.
  Future<void> applyHeadsUp(NudgeService? nudges) async {
    if (nudges == null) return;
    try {
      await nudges.setCycleHeadsUp(headsUpAt(await load()));
    } catch (_) {
      // A reminder is a bonus; never block logging.
    }
  }
}
