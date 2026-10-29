/// Guided plans: library sanity, voice cues, session position, progress.
/// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/plans/plan_library.dart';
import 'package:hux_app/core/plans/plan_models.dart';
import 'package:hux_app/core/plans/plan_progress.dart';
import 'package:hux_app/core/plans/voice_cues.dart';
import 'package:hux_app/core/profile/user_profile.dart';
import 'package:hux_app/core/storage/sqlite_health_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  group('Plan library', () {
    test('six plans, unique ids, session counts match weeks × per-week', () {
      expect(planLibrary.length, 6);
      expect(planLibrary.map((p) => p.id).toSet().length, 6);
      for (final p in planLibrary) {
        expect(p.sessions.length, p.weeks * p.sessionsPerWeek, reason: p.id);
        expect(p.sessions.every((s) => s.segments.isNotEmpty && s.totalSeconds > 0), isTrue, reason: p.id);
      }
    });

    test('Zero to 5K ends with 30 minutes of continuous running', () {
      final last = planById('zero_to_5k')!.sessions.last;
      final runs = last.segments.where((s) => s.kind == SegmentKind.run).toList();
      expect(runs.single.seconds, 30 * 60);
      expect(last.segments.first.kind, SegmentKind.warmup);
      expect(last.segments.last.kind, SegmentKind.cooldown);
    });

    test('Zero to 5K: running time grows week by week', () {
      final plan = planById('zero_to_5k')!;
      int runTime(int week) => plan.sessions
          .firstWhere((s) => s.week == week)
          .segments
          .where((s) => s.kind == SegmentKind.run)
          .fold(0, (a, s) => a + s.seconds);
      for (var w = 2; w <= 9; w++) {
        expect(runTime(w), greaterThanOrEqualTo(runTime(w - 1)), reason: 'week $w');
      }
    });

    test('Japanese interval walk: 3-minute fast/slow pairs, building to 5 sets', () {
      final plan = planById('interval_walk')!;
      int fastSets(int week) =>
          plan.sessions.firstWhere((s) => s.week == week).segments.where((s) => s.kind == SegmentKind.fast).length;
      expect([fastSets(1), fastSets(2), fastSets(3), fastSets(8)], [3, 4, 5, 5]);
      final seg = plan.sessions.last.segments.firstWhere((s) => s.kind == SegmentKind.fast);
      expect(seg.seconds, 180);
    });

    test('First Steps reaches 30 minutes; harder plans ask the readiness check', () {
      expect(planById('first_steps')!.sessions.last.minutes, 30);
      expect(planById('zero_to_5k')!.needsReadinessCheck, isTrue);
      expect(planById('interval_walk')!.needsReadinessCheck, isTrue);
      expect(planById('first_steps')!.needsReadinessCheck, isFalse);
    });

    test('Steady & Strong 60+ always has a safety note and balance exercises', () {
      final p = planById('steady_strong_60')!;
      expect(p.safetyNote, isNotNull);
      expect(p.sessions.first.segments.where((s) => s.kind == SegmentKind.exercise).length, 4);
    });

    test('recommendations follow the profile', () {
      expect(recommendedPlanIds(elder: true, fitGoal: false, weightOrSugar: false, desk: false).first, 'steady_strong_60');
      expect(recommendedPlanIds(elder: false, fitGoal: true, weightOrSugar: false, desk: false).first, 'interval_walk');
      expect(recommendedPlanIds(elder: false, fitGoal: false, weightOrSugar: false, desk: true), ['stair_snacks']);
      expect(recommendedPlanIds(elder: false, fitGoal: false, weightOrSugar: false, desk: false), ['first_steps', 'brisk_100']);
    });
  });

  group('Voice cues', () {
    const session = Session(week: 1, day: 1, segments: [
      Segment(SegmentKind.warmup, 300),
      Segment(SegmentKind.run, 60),
      Segment(SegmentKind.walk, 30),
    ]);

    test('start of each segment, halfway (long ones), 10-second warnings, and done', () {
      final cues = VoiceCues.forSession(session, CueLanguage.english);
      expect(cues.map((c) => c.atSecond), [0, 150, 290, 300, 350, 360, 390]);
      expect(cues.first.text, contains('Warm up'));
      expect(cues[3].text, contains('Start running, 1 minute'));
      expect(cues.last.text, contains('complete'));
    });

    test('Hindi cues are in Devanagari', () {
      final cues = VoiceCues.forSession(session, CueLanguage.hindi);
      expect(cues[3].text, contains('दौड़िए'));
      expect(CueLanguage.hindi.ttsTag, 'hi-IN');
      expect(CueLanguageTts.fromProfile(AppLanguage.telugu), CueLanguage.english);
    });

    test('after the phone was locked, only the latest missed cue is spoken', () {
      final cues = VoiceCues.forSession(session, CueLanguage.english);
      expect(VoiceCues.due(cues, -1, 0).single.atSecond, 0);
      expect(VoiceCues.due(cues, 0, 340).single.atSecond, 300);
      expect(VoiceCues.due(cues, 350, 351), isEmpty);
    });

    test('session position', () {
      expect(SessionPosition.of(session, 0).segmentIndex, 0);
      expect(SessionPosition.of(session, 299).secondsLeftInSegment, 1);
      expect(SessionPosition.of(session, 300).segmentIndex, 1);
      expect(SessionPosition.of(session, 390).finished, isTrue);
    });
  });

  group('PlanProgressService', () {
    Future<SqliteHealthStore> openStore() =>
        SqliteHealthStore.open(inMemoryDatabasePath, factory: databaseFactoryFfi);

    test('marks sessions done and points to the next one', () async {
      final store = await openStore();
      final svc = PlanProgressService(store);
      expect((await svc.progress('first_steps')).nextIndex, 0);
      await svc.markDone('first_steps', 0);
      await svc.markDone('first_steps', 1);
      final p = await svc.progress('first_steps');
      expect(p.nextIndex, 2);
      expect(p.fraction, closeTo(2 / 30, 1e-9));
      await store.close();
    });

    test('readiness is remembered per plan; reset clears progress', () async {
      final store = await openStore();
      final svc = PlanProgressService(store);
      await svc.confirmReadiness('zero_to_5k');
      expect((await svc.progress('zero_to_5k')).readinessConfirmed, isTrue);
      expect((await svc.progress('interval_walk')).readinessConfirmed, isFalse);
      await svc.markDone('zero_to_5k', 0);
      await svc.reset('zero_to_5k');
      expect((await svc.progress('zero_to_5k')).completed, isEmpty);
      await store.close();
    });
  });
}
