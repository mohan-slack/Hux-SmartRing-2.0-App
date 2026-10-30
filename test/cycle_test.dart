/// Cycle: predictions, phases, logging, Health import, reminders, privacy.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hux_app/core/cycle/cycle_content.dart';
import 'package:hux_app/core/cycle/cycle_health_source.dart';
import 'package:hux_app/core/cycle/cycle_models.dart';
import 'package:hux_app/core/cycle/cycle_predictor.dart';
import 'package:hux_app/core/cycle/cycle_service.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';

class _FakeSource implements CyclePeriodSource {
  final List<DateTime> days;
  _FakeSource(this.days);

  @override
  Future<List<DateTime>> bleedingDays(DateTime from, DateTime to) async => days;
}

CycleData _data(List<PeriodRecord> periods, {CycleMode mode = CycleMode.regular}) => CycleData(
      settings: CycleSettings(enabled: true, mode: mode),
      periods: periods,
    );

/// Periods every [len] days starting [first], each 5 days long.
List<PeriodRecord> _every(DateTime first, List<int> lens) {
  final out = <PeriodRecord>[];
  var s = first;
  out.add(PeriodRecord(start: s, end: addDays(s, 4)));
  for (final l in lens) {
    s = addDays(s, l);
    out.add(PeriodRecord(start: s, end: addDays(s, 4)));
  }
  return out;
}

void main() {
  sqfliteFfiInit();
  Future<SqliteHealthStore> openStore() => SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);

  group('phases', () {
    test('28-day cycle: period, follicular, ovulatory, luteal', () {
      expect(CyclePredictor.phaseForDay(1, 28, 5), CyclePhase.period);
      expect(CyclePredictor.phaseForDay(5, 28, 5), CyclePhase.period);
      expect(CyclePredictor.phaseForDay(6, 28, 5), CyclePhase.follicular);
      expect(CyclePredictor.phaseForDay(14, 28, 5), CyclePhase.ovulatory);
      expect(CyclePredictor.phaseForDay(16, 28, 5), CyclePhase.luteal);
      expect(CyclePredictor.phaseForDay(28, 28, 5), CyclePhase.luteal);
    });

    test('short cycle never puts ovulation inside the period', () {
      expect(CyclePredictor.phaseForDay(4, 18, 5), CyclePhase.period);
      expect(CyclePredictor.phaseForDay(7, 18, 5), CyclePhase.ovulatory);
    });
  });

  group('forecast', () {
    test('steady 28-day cycles: range around day 28, high confidence', () {
      final first = DateTime(2026, 3, 1);
      final periods = _every(first, [28, 28, 28, 28, 28, 28]);
      final last = periods.last.start;
      final f = CyclePredictor.forecast(_data(periods), addDays(last, 20));
      expect(f.avgCycleDays, 28);
      expect(f.dayOfCycle, 21);
      expect(f.phase, CyclePhase.luteal);
      expect(f.confidence, Confidence.high);
      expect(f.likely, addDays(last, 28));
      expect(daysBetween(f.from!, f.to!), 2); // ±1
      expect(f.isLate, isFalse);
    });

    test('no history: uses usual length, low confidence, ±3 days', () {
      final start = DateTime(2026, 10, 1);
      final f = CyclePredictor.forecast(_data([PeriodRecord(start: start)]), DateTime(2026, 10, 3));
      expect(f.periodOpen, isTrue);
      expect(f.phase, CyclePhase.period);
      expect(f.confidence, Confidence.low);
      expect(daysBetween(f.from!, f.to!), 6);
    });

    test('irregular mode widens the range and never claims high confidence', () {
      final periods = _every(DateTime(2026, 1, 1), [28, 28, 28, 28, 28, 28]);
      final f = CyclePredictor.forecast(_data(periods, mode: CycleMode.irregular), addDays(periods.last.start, 10));
      expect(daysBetween(f.from!, f.to!), greaterThanOrEqualTo(10));
      expect(f.confidence, isNot(Confidence.high));
    });

    test('late: past the range, no phase guessed', () {
      final periods = _every(DateTime(2026, 1, 1), [28, 28, 28]);
      final f = CyclePredictor.forecast(_data(periods), addDays(periods.last.start, 40));
      expect(f.isLate, isTrue);
      expect(f.phase, isNull);
      expect(f.nearWindow, isTrue);
      expect(CycleContent.statusLine(f), contains('later than usual'));
    });

    test('hormonal and pregnant: no predictions', () {
      final periods = _every(DateTime(2026, 1, 1), [28, 28]);
      for (final m in [CycleMode.hormonal, CycleMode.pregnant]) {
        final f = CyclePredictor.forecast(_data(periods, mode: m), addDays(periods.last.start, 10));
        expect(f.likely, isNull, reason: '$m');
        expect(f.phase, isNull, reason: '$m');
        expect(f.notes, isEmpty, reason: '$m');
      }
    });

    test('gentle pattern notes: 3 long cycles, long period', () {
      final periods = _every(DateTime(2026, 1, 1), [40, 41, 39]);
      final notes = CyclePredictor.patternNotes(_data(periods), addDays(periods.last.start, 5));
      expect(notes.any((n) => n.contains('longer than 35 days')), isTrue);
      final long = [PeriodRecord(start: DateTime(2026, 5, 1), end: DateTime(2026, 5, 10))];
      expect(CyclePredictor.patternNotes(_data(long), DateTime(2026, 5, 20)).any((n) => n.contains('8 days')), isTrue);
      for (final n in notes) {
        expect(n.toLowerCase(), isNot(contains('you have')));
      }
    });
  });

  group('resolver', () {
    test('past days get the phase of their own cycle', () {
      final periods = _every(DateTime(2026, 1, 1), [30, 26]);
      final r = CyclePhaseResolver(_data(periods));
      expect(r.phaseOn(DateTime(2026, 1, 2)), CyclePhase.period);
      expect(r.phaseOn(DateTime(2026, 1, 25)), CyclePhase.luteal); // day 25 of 30
      expect(r.phaseOn(DateTime(2025, 12, 1)), isNull); // before any log
    });
  });

  group('service', () {
    test('off by default; enable + log start/end; one setting key', () async {
      final store = await openStore();
      var now = DateTime(2026, 10, 1, 9);
      final cycle = CycleService(store, now: () => now);
      expect(await cycle.forecast(), isNull);
      expect(await cycle.homeSummary(), isNull);

      await cycle.enable(const CycleSettings(), lastStart: DateTime(2026, 9, 5));
      var f = (await cycle.forecast())!;
      expect(f.dayOfCycle, 27);

      await cycle.logStart(); // 1 Oct
      f = (await cycle.forecast())!;
      expect(f.periodOpen, isTrue);
      expect((await cycle.load()).periods.first.end, isNotNull, reason: 'earlier period closed');
      expect((await cycle.load()).dayLog(DateTime(2026, 10, 1)).flow, FlowLevel.medium);

      now = DateTime(2026, 10, 5, 9);
      expect(await cycle.logEnd(), isNotNull);
      f = (await cycle.forecast())!;
      expect(f.periodOpen, isFalse);
      expect((await cycle.load()).periods.last.lengthDays, 5);

      final keys = (await store.allSettings()).keys.where((k) => k.startsWith('cycle'));
      expect(keys, ['cycle_v1']);
      await store.close();
    });

    test('logging near an existing start corrects it; inside a period is a no-op', () async {
      final store = await openStore();
      final cycle = CycleService(store, now: () => DateTime(2026, 10, 10));
      await cycle.enable(const CycleSettings(), lastStart: DateTime(2026, 10, 3));
      await cycle.logStart(DateTime(2026, 10, 1));
      expect((await cycle.load()).periods.single.start, DateTime(2026, 10, 1));
      await cycle.logStart(DateTime(2026, 10, 4));
      expect((await cycle.load()).periods, hasLength(1));
      await store.close();
    });

    test('Health import groups days into periods and skips ones already logged', () async {
      final store = await openStore();
      final source = _FakeSource([
        for (var i = 0; i < 5; i++) DateTime(2026, 8, 3 + i),
        for (var i = 0; i < 4; i++) DateTime(2026, 8, 31 + i),
        DateTime(2026, 9, 28),
        DateTime(2026, 9, 30), // gap of 1 day still the same period
      ]);
      final cycle = CycleService(store, now: () => DateTime(2026, 10, 10), source: source);
      await cycle.enable(const CycleSettings(), lastStart: DateTime(2026, 9, 29));
      expect(await cycle.importFromHealth(), 2);
      final ps = (await cycle.load()).periods;
      expect(ps.map((p) => p.start), [DateTime(2026, 8, 3), DateTime(2026, 8, 31), DateTime(2026, 9, 29)]);
      expect(ps.first.lengthDays, 5);
      expect(await cycle.importFromHealth(), 0, reason: 'idempotent');
      await store.close();
    });

    test('heads-up: 9 AM two days before the range, only when asked', () async {
      final store = await openStore();
      final cycle = CycleService(store, now: () => DateTime(2026, 10, 12));
      await cycle.enable(const CycleSettings(), lastStart: DateTime(2026, 10, 1));
      expect(cycle.headsUpAt(await cycle.load()), isNull);
      final d = await cycle.updateSettings((await cycle.load()).settings.copyWith(headsUp: true));
      // likely 29 Oct, ±3 → from 26 Oct → heads-up 24 Oct 9:00
      expect(cycle.headsUpAt(d), DateTime(2026, 10, 24, 9));
      await store.close();
    });

    test('coach gets ONE phase word, only when allowed; lock hides Home details', () async {
      final store = await openStore();
      final cycle = CycleService(store, now: () => DateTime(2026, 10, 3));
      await cycle.enable(const CycleSettings(), lastStart: DateTime(2026, 10, 1));
      expect(await cycle.coachPhase(), isNull);
      await cycle.updateSettings((await cycle.load()).settings.copyWith(useInCoach: true));
      expect(await cycle.coachPhase(), 'Period');
      expect(await cycle.gentleToday(), isTrue);

      await cycle.updateSettings((await cycle.load()).settings.copyWith(lock: true));
      final home = (await cycle.homeSummary())!;
      expect(home.locked, isTrue);
      expect(home.line, isNot(contains('Period')));
      await store.close();
    });

    test('delete all wipes everything', () async {
      final store = await openStore();
      final cycle = CycleService(store, now: () => DateTime(2026, 10, 3));
      await cycle.enable(const CycleSettings(), lastStart: DateTime(2026, 10, 1));
      await cycle.deleteAll();
      final d = await cycle.load();
      expect(d.settings.enabled, isFalse);
      expect(d.periods, isEmpty);
      await store.close();
    });

    test('JSON round-trip keeps logs and settings', () {
      final d = CycleData(
        settings: const CycleSettings(enabled: true, mode: CycleMode.irregular, lock: true),
        periods: [PeriodRecord(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 5), source: 'health')],
        days: {'2026-01-02': const DayLog(flow: FlowLevel.heavy, symptoms: {Symptom.cramps})},
      );
      final back = CycleData.fromJson(d.toJson());
      expect(back.settings.mode, CycleMode.irregular);
      expect(back.settings.lock, isTrue);
      expect(back.periods.single.source, 'health');
      expect(back.dayLog(DateTime(2026, 1, 2)).symptoms, {Symptom.cramps});
    });
  });
}
